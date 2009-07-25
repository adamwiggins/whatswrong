require 'json'
require 'active_support/core_ext/time'

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

$LOAD_PATH.unshift(File.dirname(__FILE__))
require 'probe'
