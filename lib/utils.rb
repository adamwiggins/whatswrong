module Utils
	extend self

	def log_exceptions
		yield
	rescue Object => e
		puts "Exception #{e} ->"
		puts e.backtrace.map { |line| "   #{line}" }.join("\n")
	end
end
