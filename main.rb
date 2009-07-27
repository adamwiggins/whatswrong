require 'sinatra'
require File.dirname(__FILE__) + '/lib/all'

get '/' do
	erb :home
end

post '/probes' do
	probe = Probe.new(:url => params[:url].strip.downcase)
	probe.clean_url
	probe.save
	probe.enqueue
	redirect "/probes/#{probe.id}"
end

get '/probes/:id' do
	@probe = Probe.find_by_id(params[:id])

	if @probe.state != 'done'
		status 202
	end

	if request.xhr?
		erb :probe_detail, :layout => false
	else
		erb :probe
	end
end
