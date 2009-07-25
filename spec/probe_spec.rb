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
end
