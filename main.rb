require 'sinatra'
require 'uri'
require 'restclient'

get '/' do
	erb :home
end

def check(url)
	url = url.downcase.strip
	url = "http://#{url}.heroku.com/" unless url.match(/\./)
	url = "http://#{url}" unless url.match(/^http:\/\//)

	uri = URI.parse(url)
	unless `host #{uri.host}`.match(/heroku\.com\.$/)
		return "#{uri.host} is not hosted on Heroku"
	end

	begin
		RestClient.get url
		return "woot"
	rescue Object => e
		return "HTTP status code #{e.code}"
	end
end

post '/' do
	@result = check(params[:url])
end

