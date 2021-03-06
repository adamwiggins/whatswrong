require File.dirname(__FILE__) + '/base'

describe Probe do
	before do
		@probe = Probe.new
	end

	it "enqueues itself on a redis list and pops itself off again" do
		a = Probe.create(:url => 'x')
		a.enqueue
		Probe.pop_queue.id.should == a.id
	end

	it "returns nil when queue is empty" do
		Probe.pop_queue.should == nil
	end

	it "returns nil when queue key doesn't exist" do
		Probe.pop_queue.should == nil
	end

	it "normalizes headers by turning 'Content-Type: text/html' into :content_type => 'text/html'" do
		@probe.normalize_headers([ 'Content-Type: text/html' ]).should == { :content_type => 'text/html' }
	end

	describe "domain result" do
		it ":invalid_url when resolver lookup fails" do
			@probe.domain_result('ERROR', '').should == :invalid_url
		end

		it ":not_heroku when the domain does not point to proxy.heroku.com" do
			@probe.domain_result('CNAME', 'google.com').should == :not_heroku
		end

		it ":success when domain is a CNAME to heroku.com" do
			@probe.domain_result('CNAME', 'heroku.com').should == :success
		end

		it ":success when domain is a CNAME to proxy.heroku.com" do
			@probe.domain_result('CNAME', 'proxy.heroku.com').should == :success
		end
	end

	describe "http result" do
		it ":it_works when status code is 200" do
			@probe.http_result(:status => 200).first.should == :it_works
		end

		it ":it_works returns full details (http code, body size, etc)" do
			@probe.httpreq_start = 1
			Time.stubs(:now).returns(2)

			result, details = @probe.http_result(:status => 201, :content => 'abcd', :headers => [ "Content-type: text/plain", "Age: 10" ])

			details.should == {
				'http_code' => 201,
				'response_time' => 1000,
				'body_size' => 4,
				'content_type' => 'text/plain',
				'cache_age' => '10',
			}
		end

		it ":no_such_app on 404 and the hermes 'no such app' page" do
			@probe.url = 'http://myapp.heroku.com/'
			@probe.http_result(:status => 404, :content => "Heroku | No such app").should == :no_such_app
		end

		it ":domain_not_configured on 404 if it is a custom domain" do
			@probe.url = 'http://mydomain.com/'
			@probe.http_result(:status => 404, :content => "Heroku | No such app").should == :domain_not_configured
		end

		it ":rails_exception on 500 and standard rails error page" do
			@probe.http_result(:status => 500, :content => "We're sorry, but something went wrong").should == :rails_exception
		end

		it ":app_crashed when status code is 502 and crashlog_server showing backtrace" do
			@probe.http_result(:status => 502, :content => 'App failed to start').should == :app_crashed
		end

		it ":heroku_error on 503 and ouchie guy page" do
			@probe.http_result(:status => 503, :content => 'Heroku Error').should == :heroku_error
		end

		it ":backlog_too_deep on 504 and request timeout" do
			@probe.http_result(:status => 504, :content => 'Request timed out').should == :request_timeout
		end

		it ":app_exception on 500" do
			@probe.http_result(:status => 500, :content => 'boom').should == :app_exception
		end
	end
end
