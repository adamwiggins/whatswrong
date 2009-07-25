require File.dirname(__FILE__) + '/base'

class Person < Model
	property :id, :name, :age, :created_at
end

describe Model do
	it "gets attrs as a hash" do
		Person.new(:name => 'joe').attrs[:name].should == 'joe'
	end

	it "generates a random hash id" do
		Person.new.id.should.match(/^[0-9a-f]{10,30}$/)
	end

	it "sets created_at to the current time" do
		Time.stubs(:now).returns(123)
		Person.new.created_at.should == 123
	end

	it "saves to the redis db and loads it back again" do
		age = rand(99).to_s
		id = Person.create(:name => 'test', :age => age).id
		person = Person.find_by_id(id)
		person.name.should == 'test'
		person.age.should == age
	end
end
