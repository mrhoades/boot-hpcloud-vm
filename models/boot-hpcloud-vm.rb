require_relative 'novafizz'
require 'net/ssh/simple'


java_import Java.hudson.model.Environment
java_import Java.hudson.model.Result
java_import Java.hudson.util.Secret


class BootHPCloudVM < Jenkins::Tasks::Builder

  display_name 'Boot HP Cloud VM'

  attr_reader :os_username,
              :os_password,
              :os_tenant_name,
              :os_auth_url,
              :os_region_name,
              :vm_name,
              :vm_image_name,
              :vm_flavor_name,
              :vm_security_groups,
              :vm_user_data_script,
              :ssh_shell_commands,
              :ssh_shell_timeout,
              :ssh_shell_user,
              :checkbox_delete_vm_at_start,
              :checkbox_delete_vm_at_end,
              :checkbox_user_data,
              :checkbox_ssh_shell_script,
              :os_username2,
              :os_password2,
              :os_tenant_name2,
              :os_auth_url2,
              :os_region_name2,
              :vm_name2,
              :vm_image_name2,
              :vm_flavor_name2,
              :vm_security_groups2,
              :vm_user_data_script2,
              :ssh_shell_commands2,
              :ssh_shell_timeout2,
              :ssh_shell_user2


  def initialize(attrs)
    attrs.each {|k, v| instance_variable_set "@#{k}", v}
    attrs.each {|k, v| instance_variable_set "@#{k}2", v}
  end


  def perform(build, launcher, listener)

    @logger = listener
    @build = build
    @env = build.native.getEnvironment()

    inject_env_vars()
    boot_vm()
    scp_custom_script_to_vm() unless !checkbox_user_data
    execute_ssh_commands_on_vm() unless !checkbox_ssh_shell_script
  rescue Exception => e
    @logger.info "ERROR: with boot HPCloud VM"
    @logger.info e.message
    @build.native.setResult(Java.hudson.model.Result::FAILURE)
  ensure
    cleanup_vm() unless !checkbox_delete_vm_at_end
  end


  def connect_to_hpcloud
    if @novafizz == nil or @novafizz.is_openstack_connection_alive == false
       @logger.info 'Create New OpenStack Connection...'
       @novafizz = NovaFizz.new(:logger => @logger,
                               :username => os_username2,
                               :password => os_password2,
                               :authtenant => os_tenant_name2,
                               :auth_url => os_auth_url2,
                               :region => os_region_name2,
                               :service_type => 'compute')
    end
  end


  def boot_vm

    connect_to_hpcloud()

    if @novafizz.server_exists(vm_name2) == true and checkbox_delete_vm_at_start == false

      write_log "Re-Using existing VM with name '#{vm_name2}' ..."

      @creds = {:ip => @novafizz.server_by_name(vm_name2).accessipv4,
               :user => ssh_shell_user2,
               :key => @novafizz.get_key(vm_name2, File.expand_path("~/.ssh/hpcloud-keys/" + os_region_name)),
               :ssh_shell_timeout => Integer(ssh_shell_timeout2)}
    else

      if @novafizz.server_exists(vm_name2)
        write_log "Delete VM with name '#{vm_name2}'..."
        @novafizz.delete_vm_if_exists(vm_name2)
      end

      if @novafizz.keypair_exists(@novafizz.replace_period_with_dash(vm_name2))
        write_log "Delete key with name '#{@novafizz.replace_period_with_dash(vm_name2)}'..."
        @novafizz.delete_keypair_if_exists(@novafizz.replace_period_with_dash(vm_name2))
      end

      write_log "Booting a new VM..."

      @creds = @novafizz.boot :name => vm_name2,
                             :flavor => vm_flavor_name2,
                             :image => /#{vm_image_name2}/,
                             :key_name => vm_name2,
                             :region => os_region_name2,
                             :sec_groups => [vm_security_groups2],
                             :ssh_shell_user => [ssh_shell_user2]

      write_log 'VM booted at IP Address: ' + @creds[:ip]
      write_log @creds[:key]

      @creds[:ssh_shell_timeout] = Integer(ssh_shell_timeout2)

      #if vm_floating_ip != ''
      #  @novafizz.assign_floating_ip(vm_name,vm_floating_ip)
      #end

    end

    wait_for_ssh(@creds)

  end

  def scp_custom_script_to_vm()
    script_file = create_file_in_memory(vm_user_data_script2,'custom-script')
    @novafizz.scp_file(@creds, script_file, script_file. name)
    @novafizz.run_commands(@creds,"sudo chmod +x #{script_file.name}".split(','))
  end

  def execute_ssh_commands_on_vm()

      write_log "ssh #{@creds[:ssh_shell_user2]}@#{@creds[:ip]} and run commands line-by-line:"
      print_with_command_numbers(ssh_shell_commands2)

      write_log '****** BEGIN RUN COMMANDS ******'
      cmds = build_commmands_array(ssh_shell_commands2)

      @novafizz.run_commands(@creds, cmds) do |output|
        @logger.info output
      end
  end

  def print_with_command_numbers(commands_string)
    # takes a string pulled from a textarea
    # creates an array of items as numbered steps
    commands = commands_string.split(/[\n]/)

    commands.each_with_index do |cmd,index|
      @logger.info "COMMAND_#{index}: #{cmd}"
    end

  end

  def build_commmands_array(commands_string)

    # takes a string pulled from a textarea input that might contain multiple lines and splits into array.
    # wraps the commands with informative info, so when executed the output to console is more readable.

    commands = commands_string.split(/[\n]/)

    command_array = Array.new()

    commands.each_with_index do |cmd,index|

      formatted_cmd = " echo ' ' && echo ' ' && "
      formatted_cmd << " echo 'RUN_COMMAND_#{index}: #{cmd}' && echo ' ' && "
      formatted_cmd << "#{cmd}\n"

      command_array.push(formatted_cmd)
    end

    command_array
  end



  def cleanup_vm
      connect_to_hpcloud()
      write_log "Delete cloud vm and key with name '#{vm_name2}'..."
      @novafizz.delete_vm_and_key(vm_name2)
  end



  def wait_for_ssh(creds)
    write_log "Make sure SSH to #{creds[:ip]} is working. SSH into the VM and echo the hostname."
    ssh_retry_interval_seconds = 5
    ssh_retry_count = 1
    ssh_retries = 30

    begin
      @logger.info "Try ssh connect #{ssh_retry_count} of #{ssh_retries}...\n"
      @novafizz.run_commands(creds, 'hostname,hostname -d'.split(',')) do |output|
        write_log output
      end
    rescue Exception => e
      @logger.info "Connect attempt #{ssh_retry_count} of #{ssh_retries} failed ... wait #{ssh_retry_interval_seconds} seconds.\n"
      @logger.info e.message
      ssh_retry_count += 1
      sleep(ssh_retry_interval_seconds)
      retry unless ssh_retry_count == ssh_retries

      error_message = "SSH #{creds[:ssh_shell_user]}@#{creds[:ip]} timed out after #{(ssh_retry_interval_seconds*ssh_retries).to_s} seconds.\n"
      error_message << "Check defined security groups and make sure 22 is open for jenkins master or slave node."
      raise error_message
    end
  end


  def inject_env_vars
      # loop through plugin inputs2 - yes number two (it's a copy - remember this)
      # scan for pattern $MYVAR in the input text
      instance_variables.sort.each do |input| if input[-1,1] == '2'
        plugin_input_name = input.to_s
        injected_var_matches = eval(plugin_input_name).to_s.scan(/\$\w+/)
        injected_var_matches.each do |match|
          @env.each do |key, value|
            if key.to_s == match[1..-1]
              @logger.info "[Boot HP Cloud VM] - Inject var #{match} into boot VM plugin input #{plugin_input_name[1..-1].to_s}"
              updated_text = eval(plugin_input_name).gsub(match,value)
              eval("@#{plugin_input_name[1..-1]} = \"#{updated_text.to_s}\"")
            end
          end
        end
      end
    end
  end

  def create_file_in_memory(data, filename)

    # you may have permission to run a program and use memory
    # however, you may or may not have permission to write to disk
    # this appears very true with jenkins slave nodes
    # create a file in memory and save some pain
    file = StringIO.new(data)
    file.class.class_eval { attr_accessor :name }
    file.name = filename

    def file.rindex arg
      name.rindex arg
    end

    def file.[] arg
      name[arg]
    end

    def file.open(*mode, &block)
      self.rewind
      block.call(self) if block
      return self
    end

    file
  end

  def print_debug_info

    @logger.info instance_variables.to_s

    @logger.info '   '
    instance_variables.sort.each do |key, value|
      @logger.info 'PLUG-VAR: ' + key.to_s + ':' + eval(key.to_s).to_s
    end

    write_log @env.to_s
  end

  def print_sorted_array(array)
    @logger.info '   '
    array.sort.each do |value|
      @logger.info value.to_s
    end
  end

  def write_log(obj_in)
    @logger.info ' '
    @logger.info obj_in.to_s
    @logger.info ' '
  end

  def write_debug(string)
    @logger.debug ' '
    @logger.debug string
    @logger.debug ' '
  end



end #class