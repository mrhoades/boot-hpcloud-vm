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
              :result_validation_regex,
              :checkbox_delete_vm_at_start,
              :checkbox_delete_vm_at_end,
              :checkbox_user_data,
              :checkbox_ssh_shell_script,
              :checkbox_validation_regex,
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
              :result_validation_regex2


  def initialize(attrs)
    attrs.each {|k, v| instance_variable_set "@#{k}", v}
    attrs.each {|k, v| instance_variable_set "@#{k}2", v}
  end

  def prebuild(build, listener)
  end

  def perform(build, launcher, listener)

    @logger = listener
    @build = build
    @env = build.native.getEnvironment()

    inject_env_vars()

    connect_to_hpcloud()

    boot_vm()

    scp_custom_script_to_vm() unless !checkbox_user_data

    execute_ssh_commands_on_vm() unless !checkbox_ssh_shell_script

    cleanup_vm() unless !checkbox_delete_vm_at_end
  end


  def connect_to_hpcloud
    @novafizz = NovaFizz.new(:logger => @logger,
                             :username => os_username2,
                             :password => os_password2,
                             :authtenant => os_tenant_name2,
                             :auth_url => os_auth_url2,
                             :region => os_region_name2,
                             :service_type => 'compute')
  end


  def boot_vm

    if @novafizz.server_exists(vm_name2) == true and checkbox_delete_vm_at_start == false

      write_log "Re-Using existing VM with name '#{vm_name2}' ..."
      @creds = {:ip => @novafizz.server_by_name(vm_name2).accessipv4,
               :user => 'ubuntu', #bugbugbug - user should not be hardcoded
               :key => @novafizz.get_key(vm_name2, File.expand_path("~/.ssh/hpcloud-keys/" + os_region_name))}
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
                             :sec_groups => [vm_security_groups2]

      write_log 'VM booted at IP Address: ' + @creds[:ip]
      write_log @creds[:key]

      #if vm_floating_ip != ''
      #  @novafizz.assign_floating_ip(vm_name,vm_floating_ip)
      #end

    end

    wait_for_ssh(@creds)

  end

  def scp_custom_script_to_vm
    local_file = create_custom_script_file()
    remote_file = 'custom-script'
    @novafizz.scp_file(@creds, local_file, remote_file)

    #chmod that badboy
    @novafizz.run_commands(@creds,"sudo chmod +x #{remote_file}".split(','))
  end

  def execute_ssh_commands_on_vm()

      write_log "ssh ubuntu@#{@creds[:ip]} and run commands:"
      write_log ssh_shell_commands2

      full_output = ''

      write_log '****** BEGIN RUN COMMANDS ******'
      cmds = build_commmands_array(ssh_shell_commands2)

      @novafizz.run_commands(@creds, cmds) do |output|
        @logger.info output
        full_output << ' ' << output
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
      write_log "Delete cloud vm and key with name '#{vm_name}'..."
      @novafizz.delete_vm_and_key(vm_name)
  end

  def check_console_log_for_errors(output)

    return if result_validation_regex2 == '' or checkbox_validation_regex == false

    job_regex = Regexp.new(result_validation_regex2)

    matched_items = output.to_s.scan(job_regex)

    if matched_items.count() > 0

      write_log "Found match for regex '#{job_regex}' in console output!"

      matched_items.each do |item|

        write_log "***** FOUND MATCH ***** "
        write_log item

      end

      raise "Failure due to validation regex finding '#{job_regex}' in console output!"
    end
  end



  def wait_for_ssh(creds)

    write_log "Make sure SSH to #{creds[:ip]} is working. SSH into the VM and echo the hostname."

    boot_wait_seconds = 10 # it really shouldn't take much longer than to boot a vm
    ssh_retry_interval_seconds = 5
    ssh_retry_count = 20

    full_output = ''
    result=0

    for i in 1..ssh_retry_count
      begin
        @logger.info "Try ssh connect #{i} of #{ssh_retry_count}..."
        @novafizz.run_commands(creds, 'hostname,hostname -d'.split(',')) do |output|
          full_output+=output
          write_log output
        end
        break
      rescue Exception => e
        @logger.info "Connect attempt #{i} of #{ssh_retry_count} failed ... wait #{ssh_retry_interval_seconds} seconds."
        @logger.info e.message

        sleep(ssh_retry_interval_seconds)

        next
      end
    end

    if result != 0

      @logger.info "SSH ubuntu@'#{creds[:ip]}' timed out after #{(ssh_poll_interval_seconds*ssh_retry_count).to_s} seconds."
      @logger.info "Check defined security groups and make sure 22 is open for jenkins master or slave node."

      @build.native.setResult(Java.hudson.model.Result::FAILURE)
      @build.halt
    end

    return true
  end


  def create_custom_script_file

    # creates a script file from the user data provided in jenkins vm_user_data_script2

    file_path = @env['WORKSPACE'] + '/custom-script'

    begin
      File.open(file_path, 'w') do |f|
        vm_user_data_script2.split(/[\n]/).each do |line|
          f.puts(line)
        end
        f.close
      end
    rescue
      raise "Error with writing custom-script at '#{file_path}'"
    end

    file_path
  end


  def beautify_command_script(cmd)

    # split commands on line breaks
    # make sure each line ends with &&
    # add missing $$

    cleaned_script = ''
    reg_match_doubleamps = Regexp.new(/&&$/)

    cmd.split(/[\n]/).each do |line|

      if line.rstrip.lstrip == ''
      else
        if reg_match_doubleamps.match(line.lstrip.rstrip)
          cleaned_script += line.lstrip.rstrip + ' '
        else
          cleaned_line = line.lstrip.rstrip + ' && '
          cleaned_script += cleaned_line
        end
      end
    end

    # the last line no need ddollars
    cleaned_script = cleaned_script.lstrip.rstrip.chomp("&&")

    write_log 'SSH command script has been beautified for non line-by-line mode:'
    write_log cleaned_script
    write_log ' '

    cleaned_script
  end


  def inject_env_vars

      # loop through plugin inputs2 - yes number two - (it's a copy - remember this)
      # scan for pattern $MYVAR in the input text
      instance_variables.sort.each do |input| if input[-1,1] == '2'

        plugin_input_name = input.to_s
        input_instance_var_name = plugin_input_name[1..-1]

        injected_var_matches = eval(plugin_input_name).to_s.scan(/\$\w+/)
        injected_var_matches.each do |match|

          #@logger.info 'PLUGIN INPUT NAME: ' + plugin_input_name[1..-1].to_s
          #@logger.info 'MATCH VAR: ' + match[1..-1]

          @env.each do |key, value|

            if key.to_s == match[1..-1]

              @logger.info "INJECT ENV var #{match} into boot VM plugin input #{plugin_input_name[1..-1].to_s}"

              #write_log key.to_s + ':' + value
              #
              #write_log 'PERFORM REPLACE PLUGIN INPUT TEXT:'
              #write_log eval(plugin_input_name)

              updated_text = eval(plugin_input_name).gsub(match,value)

              #write_log 'UPDATED TEXT IS:'
              #write_log updated_text
              #
              #
              #write_log 'UPDATED VARIABLE IS:'
              #write_log plugin_input_name[1..-1]
              #write_log updated_text

              eval_string = "@#{plugin_input_name[1..-1]} = \"#{updated_text.to_s}\""

              #write_log 'EVAL STRING: ' + eval_string

              eval(eval_string)

              #write_log 'VARIABLE IZxxxxxZZ NOW:' + eval("@#{plugin_input_name[1..-1]}")


            end
          end
        end
      end
    end
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

  #def test_secret
  #
  #  # needs to figure out how to encrypt and decrypt password inputs
  #
  #  # shows encrypting and decrypting
  #  secret = Secret.fromString('whatthe')
  #  write_log secret
  #  write_log 'w+HH73YlwzjK4ApC/atq1K2cqkUe+Cfc0Hql8Ircx0g='
  #
  #  secret2 = Secret.toString(secret)
  #
  #  write_log secret2
  #
  #  secret3 = Secret.toString('w+HH73YlwzjK4ApC/atq1K2cqkUe+Cfc0Hql8Ircx0g=')
  #
  #  write_log secret3
  #
  #
  #end

end #class