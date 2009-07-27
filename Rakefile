task :default => 'spec:doc'

desc 'Run specs (with normal style output)'
task :spec do
	sh 'clear; bacon -q spec/*_spec.rb'
end

desc 'Run specs (with story style output)'
task 'spec:doc' do
	sh 'clear; bacon -s spec/*_spec.rb'
end

desc 'Start web app'
task 'web:start' do
	sh 'ruby main.rb -p 8200 > access.log 2>&1 &'
end

task 'worker:start' do
	sh 'ruby worker.rb > jobs.log 2>&1 &'
end

task :start => [ 'web:start', 'worker:start' ]
