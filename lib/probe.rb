require 'uri'
require 'restclient'

class Probe < Model
	property :id
	property :url
	property :state
	property :result
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

	class ProbeDone < RuntimeError; end
	class UnknownState < RuntimeError; end

	def perform
		if state == 'start'
			result = probe_domain
			if result == :success
				self.state = 'httpreq'
			else
				self.result = result
				self.state = 'done'
			end
		elsif state == 'httpreq'
			self.result = probe_http
			self.state = 'done'
		elsif state == 'done'
			raise ProbeDone
		else
			raise UnknownState, state
		end
	end

	def domain
		uri.host
	end

	def uri
		@uri ||= URI.parse(url)
	end

	def probe_domain
		self.url = "http://#{url}.heroku.com/" unless url.match(/\./)
		self.url = "http://#{url}" unless url.match(/^http:\/\//)

		begin
			uri = URI.parse(url)
		rescue URI::InvalidURIError
			return :invalid_url
		end

		return :invalid_url if uri.host.nil?

		unless `host #{uri.host}`.match(/heroku\.com\.$/)
			return :not_heroku
		end

		return :success
	end

	def probe_http
		res = RestClient.get url
		return :it_works
	rescue RestClient::Exception => e
		if e.http_code == 404 and e.response.body.match(/No such app/)
			if domain.match(/\.heroku\.com$/)
				return :no_such_app
			else
				return :domain_not_configured
			end
		end

		if e.http_code == 502 and e.response.body.match(/app failed to start/i)
			return :app_crashed
		end

		if e.http_code == 503 and e.response.body.match(/Heroku Error/)
			return :heroku_error
		end

		if e.http_code == 504 and e.response.body.match(/backlog too deep/i)
			return :backlog_too_deep
		end

		if e.http_code == 504 and e.response.body.match(/request timed out/i)
			return :request_timeout
		end

		return :it_works
	end

	def result_type
		return result if %w(it_works heroku_error).include? result.to_s
		'user_error'
	end
end
