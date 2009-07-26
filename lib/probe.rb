require 'uri'
require 'restclient'

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
			self.result, self.result_details = probe_http
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
		start = Time.now.to_f
		res = RestClient.get url
		finish = Time.now.to_f

		details = {
			'http_code' => res.code,
			'response_time' => ((finish - start) * 1000).round,
			'body_size' => res.size,
			'content_type' => res.headers[:content_type],
			'cache_age' => res.headers[:age]
		}
		return [ :it_works, details ]
	rescue RestClient::Exception => e
		if e.http_code == 404 and e.response.body.match(/No such app/)
			if domain.match(/\.heroku\.com$/)
				return :no_such_app
			else
				return :domain_not_configured
			end
		end

		if e.http_code == 500 and e.response.body.match(/We're sorry, but something went wrong/)
			return :rails_exception
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

		if e.http_code == 504 and e.response.body.match(/request timed out/i)
			return :request_timeout
		end

		return :app_exception
	end

	def result_type
		return result if %w(it_works heroku_error).include? result.to_s
		'user_error'
	end
end
