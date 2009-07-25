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
			log "Working #{probe.id} #{probe.state}"
			probe.perform
			probe.save
			probe.enqueue if probe.state != 'done'
			log "#{probe.id} next state is #{probe.state} #{probe.result ? "and result is #{probe.result}" : ''}"
		end
	end
end

