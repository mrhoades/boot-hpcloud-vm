require 'openstack'
require 'net/ssh/simple'
require 'fileutils'
require 'rubygems'

class NovaFizz

  attr_accessor :os,
                :osn,
                :logger

  def initialize(opts)

    @logger = opts[:logger]

    @logger.info "HP CLOUD CONNECTION:"
    @logger.info "USER: #{opts[:username]}"
    @logger.info "PASS: *******"
    @logger.info "TENANT_NAME: #{opts[:authtenant]}"
    @logger.info "AUTH_URL: #{opts[:auth_url]}"
    @logger.info "REGION: #{opts[:region]}"
    @logger.info "ZONE: #{opts[:availability_zone]}"
    @logger.info "SERVICE_TYPE:#{opts[:service_type]}"

    # begin
    #
    #   @logger.info 'Try connect to hp cloud using ruby fog...'
    #
    #   @fog = Fog::Compute.new(:provider => 'HP',
    #                                           :hp_access_key => '',
    #                                           :hp_secret_key => '',
    #                                           :hp_auth_uri => 'https://region-b.geo-1.identity.hpcloudsvc.com:35357/v2.0/',
    #                                           :hp_tenant_id => '',
    #                                           :hp_avl_zone => 'az1')
    #
    #   @logger.info 'Try connect to hp cloud using ruby fog...'
    #
    #   flavors = @fog.list_flavors.body['flavors']
    #
    #   @logger.info 'list flavors'
    #     @logger.info flavors.to_s
    #   @logger.info 'done list flavors'
    #
    # rescue Exception => e
    #
    #   @logger.info 'OpenStack fog connection failed...'
    #   @logger.info e.message
    #
    # end


    begin

      @logger.info 'Try connect using 1.1 style region like region-a.geo-1...'

      @os = OpenStack::Connection.create(:username => opts[:username],
                                         :api_key => opts[:password],
                                         :authtenant => opts[:authtenant],
                                         :auth_url => opts[:auth_url],
                                         :region => opts[:region],
                                         :service_type => opts[:service_type])

      @osn = OpenStack::Connection.create(:username => opts[:username],
                                         :api_key => opts[:password],
                                         :authtenant => opts[:authtenant],
                                         :auth_url => opts[:auth_url],
                                         :region => opts[:region],
                                         :service_type => "network")


    rescue Exception => e
      @logger.info e.message
      @logger.info 'Try connect using 1.0 style region like az-1.region-a.geo-1...'

      @os = OpenStack::Connection.create(:username => opts[:username],
                                         :api_key => opts[:password],
                                         :authtenant => opts[:authtenant],
                                         :auth_url => opts[:auth_url],
                                         :region => opts[:availability_zone] + '.' + opts[:region],
                                         :service_type => opts[:service_type])
    end
  end

  def is_openstack_connection_alive

    @logger.info "Check if openstack connection alive..."
    begin
      flavors = @os.flavors
      if flavors.length > 0
        @logger.info "Got some flava flav... looking alive..."
        return true
      end
    rescue Exception => e
      @logger.info "Error when checking for active connection"
      @logger.info e.message
      return false
    end

  end


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


  def print_addresses(server)
    server.addresses.each do |s|
      @logger.info s
    end
  end

  def ip_public(server)
    server.addresses.each do |s|

      @logger.info s

      if s.label == 'public'
        return s.address
      end
    end
    'address_not_set'
  end

  def ip_floating(server)
    server.addresses.each do |s|

      @logger.info s

      if s.label == 'public'
        return s.address
      end
    end
    'address_not_set'
  end

  def ip_local_nat(server)
    server.addresses.each do |s|

      @logger.info s

      if s.label == 'private'
        return s.address
      end
    end
    'address_not_set'
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

  def server_id_from_name(name)
    @os.servers.each do |s|
      return s[:id] if s[:name] == name
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

    @logger.info "Checking to see if VM with #{name} exists..."

    begin
      s = server_by_name name
      if s
        @logger.info "Found existing VM #{name}."
        return true
      end
    rescue Exception => e
      @logger.info "Error when checking if server exists."
      @logger.info e.message
      return false
    else
      @logger.info "VM #{name} does not exist."
      return false
    end
  end

  def delete_keypair_if_exists(name)
    @os.delete_keypair name if keypair_exists name
  end

  def delete_vm_if_exists(name)
    s = server_by_name name
    s.delete! if s
  end

  def wait_for_vm_delete(name)

    retry_interval_seconds = 5
    retry_count = 20

    begin
      (1..retry_count).each do |i|

        if server_exists(name)
          @logger.info "Wait attempt #{i} of #{retry_count} for deletion of VM '#{name}'... wait #{retry_interval_seconds} seconds."
          sleep(retry_interval_seconds)
        else
          return true
        end
      end
    rescue Exception => e
      @logger.info "Error in wait_for_vm_delete"
      @logger.info e.message
    end

    raise "There is an issue with deleting the vm #{name} in a timely fashion."
  end
  #
  #opts[:timeout] ||= 60
  #opts[:timeout] = 2**32 if opts[:timeout] == 0
  #opts[:operation_timeout] ||= 3600
  #opts[:operation_timeout] = 2**32 if opts[:operation_timeout] == 0
  #opts[:close_timeout] ||= 5
  #opts[:keepalive_interval] ||= 60

  def run_commands(creds, command_array)
    result = Net::SSH::Simple.sync do
      ssh(creds[:ip_floating], '/bin/bash',
          :user => creds[:user],
          :key_data => [creds[:key]],
          :timeout => creds[:ssh_shell_timeout],
          :operation_timeout => creds[:ssh_shell_operation_timeout],
          :keepalive_interval => creds[:ssh_shell_keepalive_interval],
          :global_known_hosts_file => ['/dev/null'],
          :user_known_hosts_file => ['/dev/null']) do |e,c,d|
        # e = :start, :stdout, :stderr, :exit_code, :exit_signal or :finish
        # c = our Net::SSH::Connection::Channel instance
        # d = data for this event
        case e

          # :start is triggered exactly once per connection
          when :start
            command_array.each do |cmd|
              c.send_data "#{cmd}\n"
            end
            c.eof!

          # bugbugbug - this code hangs with long running trove proboscis tests
          #when :stdout
          #  # read the input line-wise (it *will* arrive fragmented!)
          #  (@buf ||= '') << d
          #  while line = @buf.slice!(/(.*)\r?\n/)
          #    yield line.chomp if block_given?
          #  end
          #when :stderr
          #  (@buf ||= '') << d
          #  while line = @buf.slice!(/(.*)\r?\n/)
          #    yield line.chomp if block_given?
          #  end

          # :stdout is triggered when there's stdout data from remote.
          # by default the data is also appended to result[:stdout].
          # you may return :no_append as seen below to avoid that.
          when :stdout
            # read the input line-wise (it *will* arrive fragmented!)
            (@buf ||= '') << d
            while line = @buf.slice!(/(.*)\r?\n/)
              @logger.info line.chomp
            end

          # :stderr is triggered when there's stderr data from remote.
          # by default the data is also appended to result[:stderr].
          # you may return :no_append as seen below to avoid that.
          when :stderr
            # read the input line-wise (it *will* arrive fragmented!)
            (@buf ||= '') << d
            while line = @buf.slice!(/(.*)\r?\n/)
              @logger.info line.chomp
            end

          # :exit_code is triggered when the remote process exits normally.
          # it does *not* trigger when the remote process exits by signal!
          when :exit_code
            @logger.info d
            puts d

          # :exit_signal is triggered when the remote is killed by signal.
          # this would normally raise a Net::SSH::Simple::Error but
          # we suppress that here by returning :no_raise
          when :exit_signal
            @logger.info d
            :no_raise

          # :finish triggers after :exit_code when the command exits normally.
          # it does *not* trigger when the remote process exits by signal!
          when :finish
            @logger.info '** FINISHED ***'
        end
      end
    end

    # Our Result has been populated normally, except for
    # :stdout and :stdin (because we used :no_append).
    #bugbugbug - need to filter this as key appears listed
    #@logger.info e.result   # Net::SSH::Simple::Result

    if result.exit_code != 0
      @logger.debug 'RESULT EXIT CODE: ' + result.exit_code.to_s #=> 0
      @logger.debug 'RESULT STDOUT: ' + result.stdout.to_s    #=> ''
      @logger.debug 'RESULT STDERR: ' + result.stderr.to_s    #=> ''

      # bugbugbug - need option to ignore this raise as often failure doesn't mean failure
      # raise "Script failed!!! "
    else
      result.exit_code
    end

  #  if result.exit_code != 0
  #    raise "command #{result.cmd} failed on #{creds[:ip]}:\n#{result.stderr}"
  #  end
  #
  #  # bugbug - fix this up so this only shows user configures verbose loggging
  #  #if result.stderr != ''
  #  #  @logger.info "SOFT ERRORS:" + result.stderr
  #  #end
  #
  #rescue Net::SSH::Simple::Error => e
  #  raise "EXCEPTION in run_commands over ssh '#{e.result.exception}' STDERR: #{e.result.stderr}"
  end

  def write_debug(string)
    @logger.debug ' '
    @logger.debug string
    @logger.debug ' '
  end

  def write_log(string)
    @logger.info ' '
    @logger.info string
    @logger.info ' '
  end

  def scp_file(creds, local_file_path, remote_file_path)

    write_debug "SCP file #{local_file_path} to server IP #{creds[:ip_floating]} and put at #{remote_file_path}"

    begin
      Net::SSH::Simple.sync do
        r = ssh(creds[:ip_floating],'echo "Hello World"',
                :user => 'ubuntu',
                :key_data => [creds[:key]],
                :global_known_hosts_file => ['/dev/null'],
                :user_known_hosts_file => ['/dev/null'])

        if r.success and r.stdout == 'Hello World'
          @logger.info "Success! I Hello World."
        end

        r = scp_put(creds[:ip_floating], local_file_path, remote_file_path) do |sent, total|
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

  def network_uuid_from_name(name)
    # bugbugbug - watch out, neutron net-list shows an id that does not correlate to UUID
    # must query to find the REAL lesean mccoy
    @logger.debug 'network_uuid_from_name'
    networks = @osn.list_networks
    @logger.debug networks
    networks.each do |network|
      @logger.debug
      return network.id if network.name == name
    end
    raise "Neutron network with name #{name} was not found."
  end

  def prepare_create_server_hash(opts)

    # create hash object to store all values in
    vars = Hash.new
    vars[:imageRef] = image_id(opts[:image])
    vars[:flavorRef] = flavor_id(opts[:flavor])
    vars[:security_groups] = opts[:sec_groups]
    vars[:name] = opts[:name]
    vars[:personality ]= opts[:personality]

    if opts[:vm_network_name] != ''
      net_uuid = network_uuid_from_name(opts[:vm_network_name])
      vars[:networks] = [{uuid: net_uuid}]
    end

    vars
  end

  # boot an instance and return creds
  def boot(opts)

    begin
      opts.each do |key,value|
        @logger.info "#{key} : #{value}"
      end

      # set defaults if values not set
      opts[:flavor] ||= 'standard.xsmall'
      opts[:image]  ||= /Ubuntu Precise/
      opts[:sec_groups] ||= ['default']
      opts[:key_name] ||= 'default'
      opts[:region] ||= 'region-b.geo-1'
      opts[:availability_zone] ||= 'az3'
      opts[:personality] ||= {}
      opts[:ssh_shell_user] ||= 'ubuntu'
      opts[:attach_ip] ||= ''
      opts[:net_id] ||= '8a768665-f45e-4120-b568-554cde50676e'
      opts[:name] ||= opts[:vm_name]

      raise 'no name provided' if !opts[:name] or opts[:name].empty?

      server_opts = prepare_create_server_hash(opts)

      # cleanup and generate keys
      delete_vm_and_key opts[:name]
      private_key = new_key opts[:name]
      write_key(private_key, File.expand_path('~/.ssh/hpcloud-keys/' + opts[:region] + '/'))
      server_opts[:key_name] = private_key[:name]

      # boot cloud vm
      server = @os.create_server(server_opts)

      wait(300) do
        server = @os.server(server.id)
        raise 'error booting vm' if server.status == 'ERROR'
        server.status == 'ACTIVE'
      end

      @logger.info "\nTry floating IP attach..."
      if opts[:checkbox_attach_floating_ip] == 'true'
        if opts[:attach_ip] != ''
          @logger.info "\nTry attach existing ip #{opts[:attach_ip].to_s}"
          floating_ip_attach(opts[:name], opts[:attach_ip])
        else
          @logger.info "\nTry attaching an unused IP..."
          floating_ip_attach_unused(opts[:name], opts[:vm_floating_ip_pool])
        end
      end

      # scrape on final updated object
      server = @os.server(server.id)

      print_addresses(server)

      {
          :ip_floating => ip_public(server),
          :ip_public => ip_public(server),
          :ip_local_nat => ip_local_nat(server),
          :id => server.id,
          :user => opts[:ssh_shell_user],
          :key => private_key[:private_key]
      }

    rescue Net::SSH::Simple::Error => e
      @logger.info "Error occurred during bootvmn"
      @logger.info e          # Human readable error
      @logger.info e.wrapped  # Original Exception
      @logger.info e.result   # Net::SSH::Simple::Result
      raise e
    end

  end


  def floating_ip_get_list
    @os.get_floating_ips
  end

  def floating_ip_get_object(float_ip_address)
    @os.get_floating_ips.select { |f| f.ip == float_ip_address }
  end

  def floating_ip_get_object_by_id(float_id)
    @os.get_floating_ips.each do |f|
      if f.id == float_id
        return f
      end
    end
    raise "Failed in floating_ip_get_object_by_id - floating ID #{float_id} not found"
  end

  def floating_ip_get_id(float_ip_address)
    @os.get_floating_ips.each do |f|
      if f.ip == float_ip_address
        return f.id
      end
    end
    raise "Failed in floating_ip_get_id - floating IP #{float_ip_address} not found"
  end

  def floating_ip_delete(float_ip_string)

  end

  def get_unused_ip_id_list(pool)
    unattached_ip_list = []
    @logger.info "Get list of unused IPs at this moment in pool #{pool}..."
    @os.get_floating_ips.each do |ip_object|
      if ip_object.instance_id == nil && ip_object.pool == pool
        unattached_ip_list.push(ip_object.id)
      end
    end
    unattached_ip_list
  end

  def floating_ip_attach_unused(server_name, floating_ip_pool)
    # bugbubug - this is a hack/workaround for the currently broken ruby openstack which can't provision ips on hpcloud
    @logger.info "Find and attach and unused floating ip to server #{server_name}"
    retry_counter = 0
    begin
      ip_list_now = self.get_unused_ip_id_list(floating_ip_pool)
      if ip_list_now.length == 0
        raise "You don't have any available floating IPs provisioned in pool #{floating_ip_pool}. You must provision IPs in the account for prior to running this script as it only finds unused ips and attach's them."
      end

      server_id = server_id_from_name(server_name)
      sleep 5 # wait for ips to be consumed and released possibly
      ip_list_later = self.get_unused_ip_id_list(floating_ip_pool)

      unused_ip_id_list = ip_list_now & ip_list_later

      @logger.info "Found #{unused_ip_id_list.length} unused IPs."
      unused_ip_id = unused_ip_id_list.shuffle.sample()
      unused_ip = floating_ip_get_object_by_id(unused_ip_id)

      @logger.info "Attach floating ip #{unused_ip.ip} to instance id #{server_id}..."
      @os.attach_floating_ip({:server_id => server_id, :ip_id =>unused_ip.id})
    rescue Exception => e
      retry_counter += 1
      @logger.info "ERROR in floating_ip_attach_unused. Retry attempt #{retry_counter} of 5 ..."
      @logger.info e.message
      retry unless  retry_counter >= 5
      @logger.info e.backtrace
      raise 'Attach IP failed after 5 attempts.'
    end
    unused_ip.ip
  end

  def floating_ip_attach(server_name, float_ip_address)
    @logger.info "Try attach floating ip #{float_ip_address} to server with name #{server_name}..."
    server_id = server_id_from_name(server_name)
    ip_id = floating_ip_get_id(float_ip_address)
    @logger.info "Attach IP id #{ip_id} to server id #{server_id}..."
    @os.attach_floating_ip({:server_id => server_id, :ip_id =>ip_id})
  end
end
