require 'eventmachine'
require File.dirname(__FILE__) + '/lib/all'

Probe.log "=== Worker starting up"

trap 'INT' do
	Probe.log "Shutting down"
	Probe.requeue_underway
	EM.stop
	exit
end

EM.run do
	EM.add_periodic_timer(1.5) do
		Utils.log_exceptions do
			probe = Probe.pop_queue
			probe.perform if probe
		end
	end
end
