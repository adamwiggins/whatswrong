require File.dirname(__FILE__) + '/base'

describe Probe do
	it "enqueues itself on a redis list and pops itself off again" do
		a = Probe.create(:url => 'x')
		a.enqueue
		Probe.pop_queue.id.should == a.id
	end
end
