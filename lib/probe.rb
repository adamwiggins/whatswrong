require 'uri'

class Probe < Model
	property :id
	property :url
	property :state
	property :result
	property :result_details
	property :created_at
	property :updated_at

	def self.queue_key
		"#{self}:queue"
	end

	def enqueue
		DB.push_tail(Probe.queue_key, db_key)
	end

	def self.pop_queue
		key = DB.pop_head(queue_key)
		return nil unless key
		find_by_key key
	end

	def destroy
		DB.list_rm(Probe.queue_key, db_key, 0)
		super
	end

	def new_record_setup
		self.state ||= 'start'
		super
	end

	def domain
		uri.host
	end

	def uri
		@uri ||= URI.parse(url)
	end

	def normalize_headers(headers)
		out = {}
		headers.each do |string|
			key, value = string.split(': ', 2)
			key = key.downcase.gsub(/-/, '_').to_sym
			out[key] = value
		end
		out
	end

	def domain_result(dnstype, dnsdata)
		if dnstype == 'CNAME' and dnsdata.match(/heroku\.com$/)
			:success
		elsif dnstype == 'ERROR'
			:invalid_url
		else
			:not_heroku
		end
	end

	def http_result(response)
		status = response[:status]
		body = response[:content] || ''
		headers = normalize_headers response[:headers] || []

		if status.to_s.match(/^2\d\d$/)
			details = {
				'http_code' => status,
				'response_time' => ((Time.now.to_f - httpreq_start.to_f) * 1000).round,
				'body_size' => body.size,
				'content_type' => headers[:content_type],
				'cache_age' => headers[:age],
			}
			return [ :it_works, details ]
		end

		if status == 404 and body.match(/No such app/)
			if domain.match(/\.heroku\.com$/)
				return :no_such_app
			else
				return :domain_not_configured
			end
		end

		if status == 500 and body.match(/We're sorry, but something went wrong/)
			return :rails_exception
		end

		if status == 502 and body.match(/app failed to start/i)
			return :app_crashed
		end

		if status == 503 and body.match(/Heroku Error/)
			return :heroku_error
		end

		if status == 504 and body.match(/backlog too deep/i)
			return :backlog_too_deep
		end

		if status == 504 and body.match(/request timed out/i)
			return :request_timeout
		end

		if status == 504 and body.match(/request timed out/i)
			return :request_timeout
		end

		return :app_exception
	end

	def result_type
		return result if %w(it_works heroku_error).include? result.to_s
		'user_error'
	end

	class ProbeDone < RuntimeError; end
	class UnknownState < RuntimeError; end

	def perform
		log "Working #{id} #{state}"

		if state == 'start'
			probe_domain
		elsif state == 'httpreq'
			probe_http
		elsif state == 'done'
			raise ProbeDone
		else
			raise UnknownState, state
		end
	end

	def clean_url
		self.url = "http://#{url}.heroku.com/" unless url.match(/\./)
		self.url = "http://#{url}" unless url.match(/^http:\/\//)
	end

	def probe_domain
		log "DNS lookup on #{domain}"
		Probe.underway << self

		dns = Dnsruby::Resolver.new.send_async(Dnsruby::Message.new(domain))

		dns.callback do |msg|
			Utils.log_exceptions do
				msg.each_answer do |answer|
					handle_domain_result(answer.type.to_s, answer.rdata.to_s)
					break
				end
			end
		end

		dns.errback do |msg, err|
			Utils.log_exceptions do
				handle_domain_result('ERROR', '')
			end
		end
	end

	def handle_domain_result(dnstype, dnsdata)
		result = domain_result(dnstype, dnsdata)

		if result == :success
			self.state = 'httpreq'
			save
			enqueue
		else
			self.result = result
			self.state = 'done'
			save
		end

		log_state_change
	end

	attr_accessor :httpreq_start

	def probe_http
		log "Sending http request to #{url}"
		self.httpreq_start = Time.now
		Probe.underway << self

		http = EM::Protocols::HttpClient.request(
			:host => uri.host, :port => uri.port,
			:request => uri.path + (uri.query ? "?#{uri.query}" : ""))

		http.callback do |response|
			Utils.log_exceptions do
				handle_http_result(response)
			end
		end
	end

	def handle_http_result(response)
		self.result, self.result_details = http_result(response)
		self.state = 'done'
		save

		log_state_change
		Probe.underway.delete self
	end

	def log_state_change
		log "#{id} next state is #{state} #{result ? "and result is #{result}" : ''}"
	end

	def log(*args)
		self.class.log args
	end

	def self.log(msg)
		puts "[#{Time.now}] #{msg}"
	end

	def self.underway
		@underway ||= []
	end

	def self.requeue_underway
		return if underway.empty?

		log "Putting #{underway.size} httpreq probes back into the queue"
		underway.each do |probe|
			probe.enqueue
		end
		underway.clear
	end
end
