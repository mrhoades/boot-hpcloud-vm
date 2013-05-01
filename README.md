Boot-HPCloud-VM
===============

Jenkins jruby plugin that boots an openstack vm, ssh to node and run commands. Props to Tim Miller (aka echohead) for the novawhiz code, jenkins-devstack-plugin prototype, and help with debugging.

# Deploy plugin to Jenkins

* Login to your Jenkins instance as an admin user
* Manage Jenkins > Manage Plugins > Advanced Tab
* Upload the boot-hpcloud-vm.hpi plugin using the Upload dialog on Advanced Tab. Note that a build is provided for your convenience in this repo at pkg/boot-hpcloud-vm.hpi.
* Using Jenkins plugin manager, install required "Token Macro Plugin" and "ruby-runtime" plugins
* Restart Jenkins
* Now "Boot HP Cloud VM" will appear in job build steps dropdown


# Development

* `bundle install`

* `jpi server`

   -- try a jenkins version this plug should work with. download and unpack the deb with 7-zip.

* `wget http://pkg.jenkins-ci.org/debian/binary/jenkins_1.500_all.deb`

* `jpi server --war=~/jenkins_1.500_all/usr/share/jenkins/jenkins.war`


# Packaging

* `jpi build`


# Gotchas:

* "concurrent build execution" isn't supported at this time. I'm working on it though.

* must be run with ruby 1.9: `export JRUBY_OPTS=--1.9` or `echo "compat.version=1.9" >> ~/.jrubyrc`

* make sure to use jruby when building
  `rvm use jruby-1.7.2`


