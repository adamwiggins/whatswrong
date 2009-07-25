require 'sha1'

class Model
	class NoAttrsDefined < RuntimeError; end

	def self.attrs
		raise NoAttrsDefined
	end

	def attrs
		self.class.attrs.inject({}) do |a, key|
			a[key] = send(key)
			a
		end
	end

	def initialize(params={})
		params.each do |key, value|
			send("#{key}=", value)
		end
		new_record_setup unless id
	end

	def new_record_setup
		self.id = self.class.generate_id
		self.created_at = Time.now
	end

	def self.generate_id
		SHA1::sha1("#{Time.now.to_i % 392808} #{rand} #{object_id} #{self}").to_s.slice(5, 12)
	end

	def db_key
		"#{self.class}:#{id}"
	end

	def save
		self.updated_at = Time.now
		DB[db_key] = attrs.to_json
		self
	end

	def self.create(params)
		new(params).save
	end

	class RecordNotFound < RuntimeError; end

	def self.new_from_json(json)
		raise RecordNotFound unless json
		new JSON.parse(json)
	end

	def destroy
		DB.delete(db_key)
	end
end

class Probe < Model
	def self.attrs
		[ :id, :url, :state, :created_at, :updated_at ]
	end

	attr_accessor *attrs

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
