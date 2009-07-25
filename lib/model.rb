require 'sha1'

class Model
	def to_s
		"#<#{self.class} #{attrs.inspect}>"
	end

	def self.attrs
		@attrs ||= []
	end

	def self.property(*props)
		props.each do |prop|
			prop = prop.to_sym
			attrs << prop
			attr_accessor prop
		end
	end

	property :id
	property :created_at
	property :updated_at

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

	def self.db_key_for(id)
		"#{self}:#{id}"
	end

	def db_key
		self.class.db_key_for(id)
	end

	def save
		self.updated_at = Time.now
		DB[db_key] = attrs.to_json
		self
	end

	def self.create(params)
		new(params).save
	end

	def self.find(id)
		new_from_json DB[db_key_for(id)]
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
