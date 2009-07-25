require 'sinatra'
require File.dirname(__FILE__) + '/lib/all'

get '/' do
	erb :home
end

post '/probes' do
	probe = Probe.create(:url => params[:url].strip.downcase)
	redirect "/probes/#{probe.id}"
end

get '/probes/:id' do
	@probe = Probe.find_by_id(params[:id])
	erb :probe
end
