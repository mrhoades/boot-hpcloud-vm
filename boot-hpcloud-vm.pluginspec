Jenkins::Plugin::Specification.new do |plugin|
  plugin.name = "boot-hpcloud-vm"
  plugin.display_name = "Boot HP Cloud VM Plugin"
  plugin.version = '0.1.3'
  plugin.description = 'jenkins jruby plugin that boots an openstack vm ssh to node and run commands.'

  # You should create a wiki-page for your plugin when you publish it, see
  # https://wiki.jenkins-ci.org/display/JENKINS/Hosting+Plugins#HostingPlugins-AddingaWikipage
  plugin.url = 'https://wiki.jenkins-ci.org/display/JENKINS/Boot+Hpcloud+Vm+Plugin'

  # The first argument is your user name for jenkins-ci.org.
  plugin.developed_by "mrhoades", "matt.rhoades <mrhoades@hp.com>"
  plugin.developed_by 'tim.miller', 'Tim Miller <tim.miller.0@gmail.com>'

  # This specifies where your code is hosted.
  # Alternatives include:
  #  :github => 'myuser/boot-hpcloud-vm-plugin' (without myuser it defaults to jenkinsci)
  #  :git => 'git://github.com/mrhoades/boot-hpcloud-vm.git'
  #  :svn => 'https://svn.jenkins-ci.org/trunk/hudson/plugins/boot-hpcloud-vm-plugin'
  plugin.uses_repository :github => "boot-hpcloud-vm-plugin"

  # This is a required dependency for every ruby plugin.
  plugin.depends_on 'ruby-runtime', '0.10'
  plugin.depends_on 'token-macro', '1.5.1'
end
