require File.dirname(__FILE__) + '/base'

describe Probe do
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
			Probe.http_result(:status => 200).should == :it_works
		end

		it ":app_exception when status code is 500" do
			Probe.http_result(:status => 500).should == :app_exception
		end
	end
end
