
boot-hpcloud-vm
===============

jenkins jruby plugin that boots an openstack vm, ssh to node and run commands

# development

-- prep env with packages
* bundle install

-- launch a dev jenkins server including the plugin
* jpi server

-- try a jenkins version this plug should work with
-- download and unpack the deb
* wget http://pkg.jenkins-ci.org/debian/binary/jenkins_1.500_all.deb
* jpi server --war=~/jenkins_1.500_all/usr/share/jenkins/jenkins.war


# packaging
* jpi build


# Gotchas:
* must be run with ruby 1.9: `export JRUBY_OPTS=--1.9` or `echo "compat.version=1.9" >> ~/.jrubyrc`


-- props to Tim Miller for the novawhiz code, jenkins-devstack-plugin prototype, and help with debugging.


