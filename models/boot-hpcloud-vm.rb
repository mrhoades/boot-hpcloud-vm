require_relative 'novafizz'
require 'net/ssh/simple'


java_import Java.hudson.model.Environment
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
              :checkbox_commands_linebyline,
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


  @console
  @build
  @env
  @novafizz
  @creds


  def initialize(attrs)
    attrs.each {|k, v| instance_variable_set "@#{k}", v}
    attrs.each {|k, v| instance_variable_set "@#{k}2", v}
  end


  def prebuild(build, listener)


  end


  def perform(build, launcher, listener)

    @console = listener
    @build = build
    @env = build.native.getEnvironment()

    #print_debug_info()
    inject_env_vars()
    #print_debug_info()

    connect_to_hpcloud()

    boot_vm()

    execute_ssh_commands_on_vm()

    cleanup_vm()

  end


  def connect_to_hpcloud
    # bugbug - echo the credential info out to the user for debug purposes (masked password)
    @novafizz = NovaFizz.new(:username => os_username2,
                             :password => os_password2,
                             :authtenant => os_tenant_name2,
                             :auth_url => os_auth_url2,
                             :region => os_region_name2,
                             :service_type => 'compute')
  end


  def boot_vm

    if @novafizz.server_exists(vm_name2) and not checkbox_delete_vm_at_start

      write_log "Re-Using existing VM with name '#{vm_name2}' ..."
      @creds = {:ip => @novafizz.server_by_name(vm_name2).accessipv4,
               :user => 'ubuntu', #bugbugbug - user should not be hardcoded
               :key => @novafizz.get_key(vm_name2, File.expand_path("~/.ssh/hpcloud-keys/" + os_region_name))}

      #bugbugbug - currently, in this re-use flow, if the user modifies custom-script, it won't be pushed to VM
      #             custom script could be SCP'd in this case - future version


    else

      if @novafizz.server_exists(vm_name2)
        write_log "Delete cloud VM and key with name '#{vm_name2}'..."
        @novafizz.cleanup(vm_name2)
      end

      write_log "Booting a new cloud VM with name '#{vm_name2}'..."
      @creds = @novafizz.boot :name => vm_name2,
                             :flavor => vm_flavor_name2,
                             :image => /#{vm_image_name2}/,
                             :key_name => vm_name2,
                             :region => os_region_name2,
                             :sec_groups => [vm_security_groups2],
                             :personality => {create_user_script_file() => './custom-script'}

      write_log 'VM booted at IP Address: ' + @creds[:ip]
      write_log @creds[:key]


      wait_for_ssh(@creds)

      #if vm_floating_ip != ''
      #  @novafizz.assign_floating_ip(vm_name,vm_floating_ip)
      #end

    end
  end


  def execute_ssh_commands_on_vm

    if checkbox_ssh_shell_script

      write_log "ssh ubuntu@#{@creds[:ip]} and run commands:"
      write_log ssh_shell_commands2

      full_output = ''

      if checkbox_commands_linebyline

        write_log '****** BEGIN RUN COMMANDS LINE BY LINE ******'

        command_array = ssh_shell_commands2.split(/[\n]/)

        @novafizz.run_commands(@creds, command_array) do |output|
          @console.info output
          full_output += ' ' + output
        end

      else
        clean_cmd = beautify_command_script(ssh_shell_commands2)

        write_log '****** BEGIN RUN COMMAND ******'

        command_array = Array.new()

        command_array.push(clean_cmd)

        @novafizz.run_commands(@creds, command_array) do |output|
          @console.info output
          full_output += ' ' + output
        end
      end

      check_console_log_for_errors(full_output)

    end
  end



  def cleanup_vm
    if checkbox_delete_vm_at_end and @novafizz.server_exists(vm_name)
      write_log "Delete cloud vm and key with name '#{vm_name}'..."
      @novafizz.cleanup(vm_name)
    end
  end

  def check_console_log_for_errors(output)

    return if result_validation_regex2 == ''

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

  def write_log(string)
    @console.info ' '
    @console.info string
  end

  def write_debug(string)
    @console.debug ' '
    @console.debug string
  end

  def wait_for_ssh(creds)

    write_log "Make sure SSH to #{creds[:ip]} is working. SSH into the VM and echo the hostname."

    sleep(20) # because nova boot really should be this fast

    full_output = ''
    result=0

    for i in 1..30
      begin
        result= @novafizz.run_commands(creds, 'hostname') do |output|
          @console.info output
          full_output+=output
        end
        @console.info "What what... what is my name, huh, owww, too hot!"
        break
      rescue
        @console.info "Tried ssh connect #{i} of 30... not alive... wait 10 seconds and retry..."
        sleep(10)
        next
      end
    end
    if result != 0
      raise "SSH ubuntu@'#{creds[:ip]}' timed out after 300 seconds. Check defined security groups and make sure 22 is open."
    end
        # raise "Something is wonky with SSH to '#{creds[:ip]}'. Expected output from running command 'hostname' /
    #              should have been '#{vm_name}' yet '#{full_output}' was found." unless full_output == vm_name
    # bugbug - if i nova boot a vm with name matty.server.hp.com, sometimes it appears that only "matty" will show as hostname

    # bugbug - you shouldn't be hard coding timeout here
  end


  def create_user_script_file

    file_path = @env['WORKSPACE'] + 'custom-script'

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

          #@console.info 'PLUGIN INPUT NAME: ' + plugin_input_name[1..-1].to_s
          #@console.info 'MATCH VAR: ' + match[1..-1]

          @env.each do |key, value|

            if key.to_s == match[1..-1]

              @console.info "INJECT ENV var #{match} into boot VM plugin input #{plugin_input_name[1..-1].to_s}"

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

    @console.info instance_variables.to_s

    @console.info '   '
    instance_variables.sort.each do |key, value|
      @console.info 'PLUG-VAR: ' + key.to_s + ':' + eval(key.to_s).to_s
    end

    write_log @env.to_s

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