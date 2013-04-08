require 'openstack'
require 'net/ssh/simple'
require 'fileutils'

class NovaFizz

  attr_accessor :os,
                :fog,
                :logger

  def initialize(opts)

    @logger = opts[:logger]

    @logger.info "CREATE CONNECTION:"
    @logger.info "USER: #{opts[:username]}"
    @logger.info "PASS: *******"
    @logger.info "TENANT_NAME: #{opts[:authtenant]}"
    @logger.info "AUTH_URL: #{opts[:auth_url]}"
    @logger.info "REGION: #{opts[:region]}"
    @logger.info "SERVICE_TYPE:#{opts[:service_type]}"

    @os = OpenStack::Connection.create(:username => opts[:username],
                                        :api_key => opts[:password],
                                        :authtenant => opts[:authtenant],
                                        :auth_url => opts[:auth_url],
                                        :region => opts[:region],
                                        :service_type => opts[:service_type])

  end



  ## fog methods
  #
  #def fog_test_method()
  #
  #  #bugbugbug- chit no worky right now
  #
  #  #@fog = Fog::Compute.new(:provider => 'HP',
  #  #                        :hp_access_key => '',
  #  #                        :hp_secret_key => '',
  #  #                        :hp_auth_uri => 'https://region-a.geo-1.identity.hpcloudsvc.com:35357/v2.0/',
  #  #                        :hp_tenant_id => '',
  #  #                        :hp_avl_zone => 'az-1.region-a.geo-1',
  #  #                        :connection_options => {
  #  #                            :connect_timeout => 360,
  #  #                            :read_timeout => 360,
  #  #                            :write_timeout => 360,
  #  #                            :ssl_verify_peer => false})
  #  #
  #  #
  #  #servers = @fog.servers
  #  #servers.size   # returns no. of servers
  #  #               # display servers in a tabular format
  #  #@fog.servers.table([:id, :name, :state, :created_at])
  #  #@fog.addresses.table([:id, :ip, :fixed_ip, :instance_id])
  #  #
  #  #floatip_id = address_by_ip("15.185.164.224")
  #
  #end
  #
  #def assign_floating_ip(server_name,ip)
  #
  #  address = address_by_ip(ip)
  #  server = server_by_name(server_name)
  #  address.server = server
  #  address.instance_id
  #
  #end
  #
  #def fog_server_by_name(name)
  #  @fog.server.each do |s|
  #    return s if s.name == name
  #  end
  #  raise "Could not find server with name: #{name}"
  #end
  #
  #def address_by_ip(ip)
  #  @fog.addresses.each do |f|
  #    return f if f.ip == ip
  #  end
  #  raise "Could not find id of floating IP: #{ip}"
  #end
  #
  #def address_by_instance_id(instance_id)
  #  @fog.addresses.each do |f|
  #    return f if f.instance_id == instance_id
  #  end
  #  raise "Could not find ID of floating IP using instance ID: #{instance_id}"
  #end
  ## end fog methods


  def flavor_id(name)
    flavors = @os.flavors.select { |f| f[:name] == name }
    raise "ambiguous/unknown flavor: #{name}" unless flavors.length == 1
    flavors.first[:id]
  end

  def image_id(reg)
    images = @os.images.select { |i| i[:name] =~ reg }
    raise "ambiguous/unknown image: #{reg} : #{images.inspect}" unless images.length >= 1
    images.first[:id]
  end

  def replace_period_with_dash(name)
    # bugbug - handle hp cloud bug where key names with two "." can't be deleted.
    # when writing and reading keys, convert "." to "-".
    # remove this code when this openstack bug is fixed
    nameclean = name.gsub(".","-")
    return nameclean
  end

  def new_key(name)
    key = @os.create_keypair :name => replace_period_with_dash(name)
    key
  end

  def get_key_path(key_name, key_dir = File.expand_path('~/.ssh/hpcloud-keys/az-2.region-a.geo-1/'))

    path = key_dir + '/'  + replace_period_with_dash(key_name)

    if File.exist?(path)
      return path
    end
  end

  def get_key(key_name, key_dir = File.expand_path('~/.ssh/hpcloud-keys/az-2.region-a.geo-1/'))
    key = ""
    File.open(key_dir + "/"  + replace_period_with_dash(key_name), 'r') do |f|
      while line = f.gets
        key+=line
      end
    end
    return key
  end


  def write_key(key, key_dir = File.expand_path('~/.ssh/hpcloud-keys/az-2.region-a.geo-1/'))
    begin
      FileUtils.mkdir_p(key_dir) unless File.exists?(key_dir)

      keyfile_path = key_dir + "/"  + key[:name]
      File.open(keyfile_path, "w") do |f|
        f.write(key[:private_key])
        f.close
      end
      File.chmod(0600,keyfile_path)
    rescue
      raise "Error with writing key at: #{keyfile_path}"
    end
  end

  def public_ip(server)
    server.accessipv4
  end

  def wait(timeout, interval=10)
    while timeout > 0 do
      return if yield
      sleep interval
      timeout -= interval
    end
  end

  def server_by_name(name)
    @os.servers.each do |s|
      return @os.server(s[:id]) if s[:name] == name
    end
    nil
  end

  def server_list()
    return @os.servers
  end

  def keypair_name(server)
    server.key_name
  end

  def default_user(node)
    'ubuntu'
  end

  def delete_vm_and_key(name)
    delete_vm_if_exists(name)
    delete_keypair_if_exists(replace_period_with_dash(name))
  end

  def keypair_exists(name)
    kp_names = @os.keypairs.values.map { |v| v[:name] }
    return true if kp_names.include? name
  end

  def server_exists(name)
    begin
      s = server_by_name name
      return true if s
    rescue OpenStack::Exception::ItemNotFound
       @logger.info "VM with #{name} doesn't exist."
      return false
    else
      return false
    end
  end

  def delete_keypair_if_exists(name)
    @os.delete_keypair name if keypair_exists name
  end

  def delete_vm_if_exists(name)
    s = server_by_name name
    s.delete! if s
    wait_for_vm_delete(name)
  end

  def wait_for_vm_delete(name)

    ssh_retry_interval_seconds = 10 # it really shouldn't take much longer than this to delete a node
    ssh_retry_count = 10
    sleep(ssh_retry_interval_seconds)

    for i in 1..ssh_retry_count
      begin
        break unless server_exists(name)
        @logger.info "Wait attempt #{i} of #{ssh_retry_count} for deletion of vm '#{name}'... wait #{ssh_retry_interval_seconds} seconds."
        sleep(ssh_retry_interval_seconds)
      rescue Exception => e
        @logger.info e.message
        next
      end
    end

    if(server_exists(name))
      raise "There is an issue with deleting the vm #{name} in a timely fashion."
    end

  end


  def run_commands(creds, command_array)
    failed_cmd = nil
    res = Net::SSH::Simple.sync do
      ssh(creds[:ip], '/bin/bash',
          :user => creds[:user],
          :key_data => [creds[:key]],
          :timeout => 3600,
          :global_known_hosts_file => ['/dev/null'],
          :user_known_hosts_file => ['/dev/null']) do |e,c,d|
        case e
          when :start
            command_array.each do |cmd|
              failed_cmd = cmd
              c.send_data "#{cmd}\n"
            end
            c.eof!
          when :stdout
            # read the input line-wise (it *will* arrive fragmented!)
            (@buf ||= '') << d
            while line = @buf.slice!(/(.*)\r?\n/)
              yield line.chomp if block_given?
            end
          when :stderr
            (@buf ||= '') << d
            while line = @buf.slice!(/(.*)\r?\n/)
              yield line.chomp if block_given?
            end
        end
      end
    end
    if res.exit_code != 0
      raise "command #{failed_cmd} failed on #{creds[:ip]}:\n#{res.stderr}"
    end
    res
  end

  def scp_file(creds, local_file_path, remote_file_path)

    @logger.info "SCP file #{local_file_path} to server and put at #{remote_file_path}"

    begin
      Net::SSH::Simple.sync do
        r = ssh(creds[:ip], 'echo "Hello World"',
                :user => creds[:user],
                :key_data => [creds[:key]],
                :timeout => 30,
                :global_known_hosts_file => ['/dev/null'],
                :user_known_hosts_file => ['/dev/null'])
        if r.success and r.stdout == 'Hello World'
          @logger.info "Success! I Hello World."
        end

        r = scp_put(creds[:ip], local_file_path, remote_file_path) do |sent, total|
          @logger.info "Bytes uploaded: #{sent} of #{total}"
        end
        if r.success and r.sent == r.total
          @logger.info "Success! Uploaded #{r.sent} of #{r.total} bytes."
        end

      end
    rescue Net::SSH::Simple::Error => e
      @logger.info "Error with scp file to server"
      @logger.info e          # Human readable error
      @logger.info e.wrapped  # Original Exception
      @logger.info e.result   # Net::SSH::Simple::Result
      raise e
    end
  end


  # boot an instance and return creds
  def boot(opts)

    opts.each do |key,value|
      @logger.info "#{key} : #{value}"
    end

    opts[:flavor] ||= 'standard.xsmall'
    opts[:image]  ||= /Ubuntu Precise/
    opts[:sec_groups] ||= ['default']
    opts[:key_name] ||= 'default'
    opts[:region] ||= 'az-2.region-a.geo-1'
    opts[:personality] ||= {}
    raise 'no name provided' if !opts[:name] or opts[:name].empty?

    delete_vm_and_key opts[:name]
    private_key = new_key opts[:name]
    write_key(private_key, File.expand_path('~/.ssh/hpcloud-keys/' + opts[:region] + '/'))

    server = @os.create_server(
        :imageRef => image_id(opts[:image]),
        :flavorRef => flavor_id(opts[:flavor]),
        :key_name => private_key[:name],
        :security_groups => opts[:sec_groups],
        :name => opts[:name],
        :personality => opts[:personality])

    wait(300) do
      server = @os.server(server.id)
      raise 'error booting vm' if server.status == 'ERROR'
      server.status == 'ACTIVE'
    end

    {
        :ip => public_ip(server),
        :user => 'ubuntu',
        :key => private_key[:private_key]
    }
  end

end
