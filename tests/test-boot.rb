require_relative '../models/novafizz'

logger = Logger.new(STDOUT)
logger.level = Logger::INFO

@novafizz = NovaFizz.new(:logger => logger,
                         :username => 'rocket',
                         :password => 'suckmykiss',
                         :authtenant => 'rocket@hp.com-tenant1',
                         :auth_url => 'https://region-b.geo-1.identity.hpcloudsvc.com:35357/v2.0/',
                         :region => 'region-b.geo-1',
                         :availability_zone => 'az1',
                         :service_type => 'compute')

vars = Hash.new

vars[:os_username] = 'rocket'
vars[:os_password] = 'suckmykiss'
vars[:os_tenant_name] = 'rocket@hp.com-tenant1'
vars[:os_auth_url] = 'https://region-b.geo-1.identity.hpcloudsvc.com:35357/v2.0/'
vars[:os_region_name] = 'region-b.geo-1'
vars[:os_availability_zone] = 'az1'
vars[:vm_name ]= 'rocket-test-chit3333'
vars[:vm_network_name ]= 'rocketboy-network'

@novafizz.boot(vars)

