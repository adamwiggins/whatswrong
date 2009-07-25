class Probe < Model
	property :url
	property :state

	def self.queue_key
		"#{self}:queue"
	end

	def queue
		DB.push_tail(Probe.queue_key, db_key)
	end

	def destroy
		DB.list_rm(Probe.queue_key, db_key, 0)
		super
	end

	def new_record_setup
		self.state = 'start'
		super
	end
end
