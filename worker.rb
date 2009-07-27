require 'eventmachine'
require File.dirname(__FILE__) + '/lib/all'

def log(msg)
	puts "[#{Time.now}] #{msg}"
end

log "=== Worker starting up"

$httpreqs = []

trap 'INT' do
	log "Shutting down"

	if $httpreqs.size > 0
		log "(putting #{$httpreqs.size} httpreq probes back into the queue)"
		$httpreqs.each do |probe|
			probe.enqueue
		end
	end

	EM.stop
	exit
end

EM.run do
	EM.add_periodic_timer(1.5) do
		probe = Probe.pop_queue
		if probe
			log "Working #{probe.id} #{probe.state}"

			if probe.state == 'httpreq'
				log "Sending http request to #{probe.url}"
				$httpreqs << probe

			   http = EM::Protocols::HttpClient.request(:host => probe.uri.host, :port => probe.uri.port, :request => probe.uri.path)

	   		http.callback do |r|
					probe.result, probe.result_details = Probe.http_result(r)
					probe.state = 'done'
					probe.save
					log "#{probe.id} next state is #{probe.state} #{probe.result ? "and result is #{probe.result}" : ''}"
					$httpreqs.delete probe
			   end
			else
				probe.perform
				probe.save
				probe.enqueue if probe.state != 'done'
				log "#{probe.id} next state is #{probe.state} #{probe.result ? "and result is #{probe.result}" : ''}"
			end
		end
	end
end

