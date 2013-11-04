class BootVMPluginVars
  attr_accessor :os_username,
                :os_password,
                :os_tenant_name,
                :os_auth_url,
                :os_region_name,
                :vm_name,
                :vm_image_name,
                :vm_flavor_name,
                :vm_security_groups,
                :vm_floating_ip,
                :vm_user_data_script,
                :ssh_shell_commands,
                :ssh_shell_timeout,
                :ssh_shell_operation_timeout,
                :ssh_shell_keepalive_interval,
                :ssh_shell_user,
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
                :verbose_logging_enabled,
                :creds
end

