Boot-HPCloud-VM
===============

Jenkins jruby plugin that boots an openstack vm, ssh to node and run commands. Props to Tim Miller (aka echohead) for the novawhiz code, jenkins-devstack-plugin prototype, and help with debugging.

# Deploy plugin to Jenkins

1. Login to your Jenkins instance as an admin user
* Manage Jenkins > Manage Plugins > Advanced Tab
* Upload the boot-hpcloud-vm.hpi plugin using the Upload dialog on Advanced Tab. Note that a build is provided for your convenience in this repo at pkg/boot-hpcloud-vm.hpi.
* Using Jenkins plugin manager, install required "Token Macro Plugin" and "ruby-runtime" plugins
* Restart Jenkins
* Now "Boot HP Cloud VM" will appear in job build steps dropdown


# Development

=== Install ruby 2.x and jruby 1.7.3
* `curl -#L https://get.rvm.io | bash -s stable --autolibs=3 --ruby`
* `source ~/.rvm/scripts/rvm`
* `rvm install jruby`

=== Git the source code

* `git clone git://github.com/mrhoades/boot-hpcloud-vm.git`
* `cd boot-hpcloud-vm`

=== Debug with 'Jenkins Ruby Plugin Tools'
* `rvm use jruby-1.7.3`
* `bundle install`
* `gem install jpi` 
* `jpi server`
* Now see plugin in jenkins at http://localhost:8080

=== Build Plugin with 'Jenkins Ruby Plugin Tools'
* `jpi build` 

=== Getting Started Developing Ruby Plugins
* https://github.com/jenkinsci/jenkins.rb/wiki/Getting-Started-With-Ruby-Plugins

