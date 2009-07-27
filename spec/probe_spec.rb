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

	describe "state machine" do
		it "start -> probe_domain -> not_heroku" do
			probe = Probe.new(:state => 'start')
			probe.stubs(:probe_domain).returns(:not_heroku)
			probe.perform
			probe.result.should == :not_heroku
			probe.state.should == 'done'
		end

		it "start -> probe_domain -> success, go to httpreq state" do
			probe = Probe.new(:state => 'start')
			probe.stubs(:probe_domain).returns(:success)
			probe.perform
			probe.result.should == nil
			probe.state.should == 'httpreq'
		end

		it "httpreq -> probe_http -> final state, result is recorded straight to db" do
			probe = Probe.new(:state => 'httpreq')
			probe.stubs(:probe_http).returns(:whatever)
			probe.perform
			probe.result.should == :whatever
			probe.state.should == 'done'
		end
	end

	describe "http result" do
		it ":it_works when status code is 200" do
			@probe.http_result(:status => 200).first.should == :it_works
		end

		it ":it_works returns full details (http code, body size, etc)" do
			result, details = @probe.http_result(:status => 201, :content => 'abcd', :headers => [ "Content-type: text/plain", "Age: 10" ])
			details.should == {
				'http_code' => 201,
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
