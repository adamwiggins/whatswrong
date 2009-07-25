class Probe < Model
	property :id
	property :url
	property :state
	property :created_at
	property :updated_at

	def self.queue_key
		"#{self}:queue"
	end

	def enqueue
		DB.push_tail(Probe.queue_key, db_key)
	end

	def self.pop_queue
		find_by_key DB.pop_head(queue_key)
	end

	def perform
		puts "running probe"
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
