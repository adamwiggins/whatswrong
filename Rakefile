task :default => 'spec:doc'

desc 'Run specs (with normal style output)'
task :spec do
	sh 'bacon -q spec/*_spec.rb'
end

desc 'Run specs (with story style output)'
task 'spec:doc' do
	sh 'bacon -s spec/*_spec.rb'
end
