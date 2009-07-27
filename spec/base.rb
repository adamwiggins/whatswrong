ENV['REDIS_URL'] = 'redis://localhost:6379/15'

require File.dirname(__FILE__) + '/../lib/all'

class Probe
	def self.log(msg)
	end
end

require 'bacon'
require 'mocha/api'
require 'mocha/object'

class Bacon::Context
	include Mocha::API

	def initialize(name, &block)
		@name = name
		@before, @after = [
			[lambda { mocha_setup ; DB.flush_db }],
			[lambda { mocha_verify ; mocha_teardown }]
		]
		@block = block
	end

	def xit(desc, &bk)
	end
end
