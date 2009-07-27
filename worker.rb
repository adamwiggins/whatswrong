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
		probe = Probe.pop_queue
		next unless probe

		probe.perform
	end
end
