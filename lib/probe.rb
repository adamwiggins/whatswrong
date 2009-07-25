class Probe < Model
	property :id
	property :url
	property :state
	property :created_at
	property :updated_at

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
