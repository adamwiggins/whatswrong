require 'json'

$LOAD_PATH.unshift File.dirname(__FILE__) + '/../vendor/redis'
require 'redis'

redis_config = if ENV['REDIS_URL']
	require 'uri'
	uri = URI.parse ENV['REDIS_URL']
	{ :host => uri.host, :port => uri.port, :password => uri.password, :db => uri.path.gsub(/^\//, '') }
else
	{}
end

DB = Redis.new(redis_config)

require 'eventmachine'
require 'Dnsruby'

Dnsruby::Resolver.use_eventmachine
Dnsruby::Resolver.start_eventmachine_loop(false)

$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'model'
require 'probe'
require 'utils'
