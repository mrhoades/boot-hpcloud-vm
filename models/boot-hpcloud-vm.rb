require_relative 'novafizz'
require_relative 'boot_vm_concurrent'
require_relative 'boot_vm_vars'
require_relative 'ssh'
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
              :os_availability_zone,
              :vm_name,
              :vm_image_name,
              :vm_flavor_name,
              :vm_security_groups,
              :vm_floating_ip,
              :vm_floating_ip_pool,
              :vm_user_data_script,
              :ssh_shell_commands,
              :ssh_shell_commands1,
              :ssh_shell_commands2,
              :ssh_shell_timeout,
              :ssh_shell_timeout1,
              :ssh_shell_timeout2,
              :ssh_shell_operation_timeout,
              :ssh_shell_keepalive_interval,
              :ssh_shell_user,
              :ssh_authorized_public_key,
              :ssh_connect_retry_int,
              :ssh_fail_on_soft_error,
              :checkbox_delete_vm_at_start,
              :checkbox_delete_vm_at_end,
              :checkbox_user_data,
              :checkbox_ssh_shell_script,
              :checkbox_custom_retry,
              :checkbox_attach_floating_ip,
              :retry_connect_hpcloud_int,
              :retry_create_vm_int,
              :retry_delete_vm_int,
              :checkbox_verbose_logging_enabled,
              :stderr_lines_int

  def initialize(attrs)
    attrs.each {|k, v| instance_variable_set "@#{k}", v}
  end

  def perform(build, launcher, listener)

    vars = BootVMVars.new()
    fill_vars_object(vars)
    bootvm = BootVMConcurrent.new(build, listener, vars)

    # global timeout - sum of all major time consumers
    timeout = vars.ssh_shell_timeout.to_i + vars.ssh_shell_timeout1.to_i
    timeout += vars.ssh_shell_timeout2.to_i + 600
    # time for booting the vm (bugbugbug - hardcoded value)
    listener.info 'JOB_TIMEOUT: ' + timeout.to_s

    bootvm_thread = Thread.new{
      Timeout::timeout(timeout) {bootvm.geter_done}
    }
    bootvm_thread.join

  rescue Exception => e
    listener.info "Error Caught in Main Perform: "
    listener.info e.message
    listener.info e.backtrace
  ensure
    cleanup_thread = Thread.new{
      Timeout::timeout(120) {bootvm.cleanup}
    }
    cleanup_thread.join
  end

  def fill_vars_object(vars)
    instance_variables.sort.each do |input|
      input_name = input.to_s[1..-1]
      input_value = eval(input.to_s)
      eval_string = "vars.#{input_name} = %Q[#{input_value.to_s}]"
      eval(eval_string)
    end
    vars
  end

end #class