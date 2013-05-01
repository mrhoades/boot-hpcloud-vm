
class BootVMConcurrent

  attr_accessor :os_username,
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
                :ssh_connect_retry_int,
                :ssh_fail_on_soft_error,
                :checkbox_delete_vm_at_start,
                :checkbox_delete_vm_at_end,
                :checkbox_user_data,
                :checkbox_ssh_shell_script,
                :checkbox_custom_retry,
                :retry_connect_hpcloud_int,
                :retry_create_vm_int,
                :retry_delete_vm_int,
                :checkbox_verbose_logging_enabled


  def initialize(build, listener, vars_in)

    @logger = listener
    @build = build
    @env = build.native.getEnvironment()
    @vars = vars_in

    inject_env_vars()

    #test_concurrency(build, listener)

    boot_vm()
    scp_custom_script_to_vm() unless !@vars.checkbox_user_data
    execute_ssh_commands_on_vm() unless !@vars.checkbox_ssh_shell_script

  rescue Exception => e
    @logger.info "*******************\n****** ERROR-ERROR-BEGIN ******\n"
    @logger.info e.message
    @logger.info "\n****** ERROR-ERROR-END ******\n*******************\n"

    @build.native.setResult(Java.hudson.model.Result::FAILURE)
  ensure
    begin
      @logger.info "\n****** CLEANUP ******\n"
      delete_vm_and_key()
    end unless !@vars.checkbox_delete_vm_at_end
  end

  def test_concurrency(build, listener)

    @logger.info @env['BUILD_TAG']

    (1...5).each do |i|
      @logger.info "Value of local #{@env['BUILD_TAG']} variable is #{i}"
      puts "Value of local #{@env['BUILD_TAG']} variable is #{i}"
      sleep 1
    end
  end


  def connect_to_hpcloud
    if @novafizz == nil or @novafizz.is_openstack_connection_alive == false
      begin
        write_log 'Create New HP Cloud Compute Connection...'
        @novafizz = NovaFizz.new(:logger => @logger,
                                 :username => @vars.os_username,
                                 :password => @vars.os_password,
                                 :authtenant => @vars.os_tenant_name,
                                 :auth_url => @vars.os_auth_url,
                                 :region => @vars.os_region_name,
                                 :service_type => 'compute')
      rescue Exception => e
        @logger.info "Connect to HP Cloud Compute failed ... wait 5 seconds and retry."
        @logger.info e.message
        sleep(5)
        counter += 1

        retry unless  counter >= retry_connect_hpcloud_int.to_i
        raise "Connect to HP Cloud Compute failed after #{retry_connect_hpcloud_int} retries."
      end
    end
  end


  def boot_vm

    connect_to_hpcloud()

    if @novafizz.server_exists(@vars.vm_name) == true and checkbox_delete_vm_at_start == false

      write_log "Re-Using existing VM with name '#{@vars.vm_name}' ..."

      @vars.creds = {:ip => @novafizz.server_by_name(@vars.vm_name).accessipv4,
                     :user => @vars.ssh_shell_user,
                     :key => @novafizz.get_key(@vars.vm_name, File.expand_path("~/.ssh/hpcloud-keys/" + @vars.os_region_name)),
                     :ssh_shell_timeout => @vars.ssh_shell_timeout.to_i}
    else
      delete_vm_and_key()

      write_log "Booting a new VM..."

      @vars.creds = @novafizz.boot :name => @vars.vm_name,
                                   :flavor => @vars.vm_flavor_name,
                                   :image => /#{@vars.vm_image_name}/,
                                   :key_name => @vars.vm_name,
                                   :region => @vars.os_region_name,
                                   :sec_groups => [@vars.vm_security_groups],
                                   :ssh_shell_user => [@vars.ssh_shell_user]

      write_log 'VM booted at IP Address: ' + @vars.creds[:ip]
      write_debug @vars.creds[:key]

      @vars.creds[:ssh_shell_timeout] = @vars.ssh_shell_timeout.to_i

      #if vm_floating_ip != ''
      #  @novafizz.assign_floating_ip(vm_name,vm_floating_ip)
      #end
    end
    wait_for_ssh(@vars.creds)
  end

  def scp_custom_script_to_vm
    script_file = create_file_in_memory(@vars.vm_user_data_script.to_s, @vars.vm_name, 'custom-script')
    @novafizz.scp_file(@vars.creds, script_file, script_file.name_remote)
    @novafizz.run_commands(@vars.creds,"sudo chmod +x #{script_file.name_remote}".split(','))
  end

  def execute_ssh_commands_on_vm
    write_log '****** COMMAND SUMMARY ******'
    write_log "ssh #{@vars.ssh_shell_user}@#{@vars.creds[:ip]} and run commands line-by-line:"
    print_with_command_numbers(@vars.ssh_shell_commands)
    write_log '****** BEGIN RUN COMMANDS ******'
    cmds = build_commmands_array(@vars.ssh_shell_commands)
    @novafizz.run_commands(@vars.creds, cmds) do |output|
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
      formatted_cmd << " echo \"COMMAND_#{index}: #{cmd}\" && echo ' ' && "
      formatted_cmd << "#{cmd}\n"

      command_array.push(formatted_cmd)
    end

    command_array
  end

  def delete_vm_and_key
    connect_to_hpcloud()
    begin
      if(@novafizz.server_exists(@vars.vm_name))
        write_log "Delete cloud VM and key with name '#{@vars.vm_name}'..."
        @novafizz.delete_vm_and_key(@vars.vm_name)
        @novafizz.wait_for_vm_delete(@vars.vm_name)
      end
    rescue Exception => e
      @logger.info "Delete VM #{@vars.vm_name} failed ... wait 5 seconds and retry."
      @logger.info e.message
      sleep(5)
      counter += 1

      retry unless @vars.retry_delete_vm_int.to_i <= counter
      raise "Delete VM '#{@vars.vm_name}' failed failed after #{@vars.retry_delete_vm_int} retries."
    end
  end

  def wait_for_ssh(creds)
    write_log "Make sure SSH to #{creds[:ip]} is working. SSH into the VM and echo the hostname."
    ssh_retry_interval_seconds = 5
    ssh_retry_count = 1

    begin
      @logger.info "Try ssh connect #{ssh_retry_count} of #{@vars.ssh_connect_retry_int}...\n"
      @novafizz.run_commands(creds, "echo 'SUCCESSFULLY CONNECTED to VM over SSH!',hostname,hostname -d".split(',')) do |output|
        write_log output
      end
    rescue Exception => e
      @logger.info "Connect attempt #{ssh_retry_count} of #{@vars.ssh_connect_retry_int} failed ... wait #{ssh_retry_interval_seconds} seconds.\n"
      @logger.info e.message
      ssh_retry_count += 1
      sleep(ssh_retry_interval_seconds)

      retry unless @vars.ssh_connect_retry_int.to_i < ssh_retry_count

      error_message = "SSH #{@vars.ssh_shell_user}@#{creds[:ip]} timed out after #{(ssh_retry_interval_seconds*@vars.ssh_connect_retry_int.to_i).to_s} seconds.\n\n"
      error_message << "Check defined security groups and make sure 22 is open for jenkins master or slave node."
      raise error_message
    end
  end

  def create_file_in_memory(data, filename_local, filename_remote)

    # you may have permission to run a program and use memory
    # however, you may or may not have permission to write to disk
    # this appears very true with jenkins slave nodes
    # create a file in memory and save some pain
    file = StringIO.new(data)
    file.class.class_eval { attr_accessor :name,:name_remote }
    file.name_remote = filename_remote
    file.name = filename_local

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


  def inject_env_vars
    write_debug @vars.inspect
    @vars.instance_variables.each do |attr_name|
      plugin_input_name = "@vars.#{attr_name[1..-1]}"
      injected_var_matches = @vars.instance_variable_get(attr_name).to_s.scan(/\$\w+/)
      injected_var_matches.each do |match|
        @env.each do |key, value|
          if key.to_s == match[1..-1]
            @logger.info "[Boot HP Cloud VM] - Inject var '#{match}' with value '#{value}' into boot VM plugin input #{attr_name[1..-1]}"
            updated_text = eval(plugin_input_name).gsub(match,value)
            eval("#{plugin_input_name} = \"#{updated_text.to_s}\"")
          end
        end
      end
    end
    write_debug @vars.inspect
  end


  def print_debug_info

    @logger.info instance_variables.to_s

    @logger.info '   '
    instance_variables.sort.each do |key, value|
      @logger.info 'VARS: ' + key.to_s + ':' + eval(key.to_s).to_s
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
    if @vars.checkbox_verbose_logging_enabled == 'true'
      @logger.debug ' '
      @logger.debug string.to_s
      @logger.debug ' '
    end
  end

end
