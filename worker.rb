require 'eventmachine'
require File.dirname(__FILE__) + '/lib/all'

def log(msg)
	puts "[#{Time.now}] #{msg}"
end

log "=== Worker starting up"

trap 'INT' do
	log "Shutting down"
	EM.stop
	exit
end

EM.run do
	EM.add_periodic_timer(0.5) do
		probe = Probe.pop_queue
		if probe
			log "Working #{probe}"
			probe.perform
			probe.save
		end
	end
end

