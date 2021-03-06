#--
#Copyright 2007 Nominet UK
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License. 
#You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0 
#
#Unless required by applicable law or agreed to in writing, software 
#distributed under the License is distributed on an "AS IS" BASIS, 
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
#See the License for the specific language governing permissions and 
#limitations under the License.
#++
module Dnsruby
  ClassHash = {} #:nodoc: all
  
  # RFC2181, section 5
  # "It is however possible for most record types to exist
  # with the same label, class and type, but with different data.  Such a
  # group of records is hereby defined to be a Resource Record Set
  # (RRSet)."
  class RRSet
    def initialize()
      @rrs = []
    end
    #Add the RR to this RRSet
    def add(r)
      if @rrs.include?r
        return false
      end
      if (rrs.size() == 0)
        @rrs.push(r)
        return;
      end
      # Check the type, klass and ttl are correct
      first = @rrs[0]
      if (!r.sameRRset(first))
        raise ArgumentError.new("record does not match rrset")
      end
      
      if (r.ttl != first.ttl) # RFC2181, section 5.2
        if (r.ttl > first.ttl)
          #          r = r.cloneRecord();
          r.ttl=(first.ttl);
        else
          @rrs.each do |rr|
            rr.ttl = r.ttl
          end
        end
      end
      
      if (!rrs.contains(r))
        @rrs.push(r)
      end
    end
    
    #Delete the RR from this RRSet
    def delete(rr)
      @rrs.delete(rr)
    end
    def each
      @rrs.each do |rr|
        yield rr
      end
    end
    #Return the type of this RRSet
    def type
      return @rrs[0].type
    end
    #Return the klass of this RRSet
    def klass
      return @rrs[0].klass
    end
    #Return the ttl of this RRSet
    def ttl
      return @rrs[0].ttl
    end
  end
  
  #Superclass for all Dnsruby resource records.
  # 
  #Represents a DNS RR (resource record) [RFC1035, section 3.2]
  # 
  #Use Dnsruby::RR::create(...) to create a new RR record. 
  # 
  #   mx = Dnsruby::RR.create("example.com. 7200 MX 10 mailhost.example.com.")
  #   
  #   rr = Dnsruby::RR.create({:name => "example.com", :type => "MX", :ttl => 7200, 
  #                                  :preference => 10, :exchange => "mailhost.example.com"})
  #                                  
  #   s = rr.to_s # Get a String representation of the RR (in zone file format)
  #   rr_again = Dnsruby::RR.create(s)
  # 
  class RR
    
    # A regular expression which catches any valid resource record.
    @@RR_REGEX = Regexp.new("^\\s*(\\S+)\\s*(\\d+)?\\s*(#{Classes.regexp + "|CLASS\\d+"})?\\s*(#{Types.regexp + '|TYPE\\d+'})?\\s*([\\s\\S]*)\$") #:nodoc: all
    
    #The Resource's domain name
    attr_reader :name
    #The Resource type
    attr_reader :type
    #The Resource class
    attr_reader :klass
    #The Resource Time-To-Live
    attr_accessor :ttl
    #The Resource data section
    attr_accessor :rdata
    
    def rdlength
      return rdata.length
    end
    
    def name=(newname)
      if (!(newname.kind_of?Name))
        @name=Name.create(newname)
      else
        @name = newname
      end
    end
    
    def type=(type)
      @type = Types.new(type)
    end
    alias :rr_type :type
    
    def klass=(klass)
      @klass= Classes.new(klass)
    end
    
    # Determines if two Records could be part of the same RRset.
    # This compares the name, type, and class of the Records; the ttl and
    # rdata are not compared.
    def sameRRset(rec)
      return (@type == rec.type && @klass == rec.klass && @name== rec.name)
    end
    
    def init_defaults
      # Default to do nothing
    end
    
    private
    def initialize(*args) #:nodoc: all
      init_defaults
      if (args.length > 0)
        if (args[0].class == Hash)
          from_hash(args[0])
          return
        else
          @rdata = args[0]
          if (args[0].class == String)
            from_string(args[0])
            return
          else
            from_data(args[0])
            return
          end
        end
      end
      #      raise ArgumentError.new("Don't call new! Use Dnsruby::RR::create() instead")
    end
    public
    
    def from_hash(hash) #:nodoc: all
      hash.keys.each do |param|
        send(param.to_s+"=", hash[param])
      end
    end
    
    #Create a new RR from the hash. The name is required; all other fields are optional.
    #Type defaults to ANY and the Class defaults to IN. The TTL defaults to 0.
    #
    #If the type is specified, then it is necessary to provide ALL of the resource record fields which 
    #are specific to that record; i.e. for
    #an MX record, you would need to specify the exchange and the preference
    #
    #   require 'Dnsruby'
    #   rr = Dnsruby::RR.new_from_hash({:name => "example.com"})
    #   rr = Dnsruby::RR.new_from_hash({:name => "example.com", :type => Types.MX, :ttl => 10, :preference => 5, :exchange => "mx1.example.com"})
    def RR.new_from_hash(inhash)
      hash = inhash.clone        
      type = hash[:type] || Types::ANY
      klass = hash[:klass] || Classes::IN
      ttl = hash[:ttl] || 0
      recordclass = get_class(type, klass)
      record = recordclass.new
      record.name=hash[:name]
      if !(record.name.kind_of?Name)
        record.name = Name.create(record.name)
      end
      record.ttl=ttl
      record.type = type
      record.klass = klass
      hash.delete(:name)
      hash.delete(:type)
      hash.delete(:ttl)
      hash.delete(:klass)
      record.from_hash(hash)
      return record
    end
    
    #Returns a Dnsruby::RR object of the appropriate type and
    #initialized from the string passed by the user.  The format of the
    #string is that used in zone files, and is compatible with the string
    #returned by Net::DNS::RR.inspect
    #
    #The name and RR type are required; all other information is optional.
    #If omitted, the TTL defaults to 0 and the RR class defaults to IN.
    #
    #All names must be fully qualified.  The trailing dot (.) is optional.
    #
    # 
    #   a     = Dnsruby::RR.new_from_string("foo.example.com. 86400 A 10.1.2.3")
    #   mx    = Dnsruby::RR.new_from_string("example.com. 7200 MX 10 mailhost.example.com.")
    #   cname = Dnsruby::RR.new_from_string("www.example.com 300 IN CNAME www1.example.com")
    #   txt   = Dnsruby::RR.new_from_string('baz.example.com 3600 HS TXT "text record"')
    #
    #
    def RR.new_from_string(rrstring)
      # strip out comments
      # Test for non escaped ";" by means of the look-behind assertion
      # (the backslash is escaped)
      rrstring.gsub!(/(\?<!\\);.*/o, "");
      
      if ((rrstring =~/#{@@RR_REGEX}/xo) == nil)
        raise Exception, "#{rrstring} did not match RR pat.\nPlease report this to the author!\n"
      end
      
      name    = $1;
      ttl     = $2.to_i || 0;
      rrclass = $3 || '';
      
      
      rrtype  = $4 || '';
      rdata   = $5 || '';
      
      if rdata 
        rdata.gsub!(/\s+$/o, "")
      end
      if name 
        name.gsub!(/\.$/o, "");
      end
      
      
      # RFC3597 tweaks
      # This converts to known class and type if specified as TYPE###
      if rrtype  =~/^TYPE\d+/o
        rrtype  = Dnsruby::Types.typesbyval(Dnsruby::Types::typesbyname(rrtype))
      end
      if rrclass =~/^CLASS\d+/o
        rrclass = Dnsruby::Classes.classesbyval(Dnsruby::Classes::classesbyname(rrclass))
      end
      
      
      if (rrtype=='' && rrclass && rrclass == 'ANY')
        rrtype  = 'ANY';
        rrclass = 'IN';
      elsif (rrclass=='')
        rrclass = 'IN';
      end
      
      if (rrtype == '')
        rrtype = 'ANY';
      end
      
      if (implemented_rrs.include?(rrtype) && rdata !~/^\s*\\#/o )
        subclass = _get_subclass(name, rrtype, rrclass, ttl, rdata)
        return subclass
      elsif (implemented_rrs.include?(rrtype))   # A known RR type starting with \#
        rdata =~ /\\\#\s+(\d+)\s+(.*)$/o;
        
        rdlength = $1.to_i;
        hexdump  = $2;		
        hexdump.gsub!(/\s*/, "");
        
        if hexdump.length() != rdlength*2
          raise Exception, "#{rdata} is inconsistent; length does not match content"
        end
        
        rdata = [hexdump].pack('H*');
        
        return new_from_data(name, rrtype, rrclass, ttl, rdlength, rdata, 0) # rdata.length() - rdlength);
      elsif (rdata=~/\s*\\\#\s+\d+\s+/o)
        #We are now dealing with the truly unknown.
        raise Exception, 'Expected RFC3597 representation of RDATA' unless rdata =~/\\\#\s+(\d+)\s+(.*)$/o;
        
        rdlength = $1.to_i;
        hexdump  = $2;		
        hexdump.gsub!(/\s*/o, "");
        
        if hexdump.length() != rdlength*2
          raise Exception, "#{rdata} is inconsistent; length does not match content" ;
        end
        
        rdata = [hexdump].pack('H*');
        
        return new_from_data(name,rrtype,rrclass,ttl,rdlength,rdata,0) # rdata.length() - rdlength);
      else
        #God knows how to handle these...
        subclass = _get_subclass(name, rrtype, rrclass, ttl, "")
        return subclass
      end
    end
    
    def RR.new_from_data(*args) #:nodoc: all
      name = args[0]
      rrtype = args[1]
      rrclass = args[2]
      ttl = args[3]
      rdlength = args[4]
      data = args[5]
      offset = args[6]
      rdata = data[offset, rdlength]
      
      record = nil
      MessageDecoder.new(rdata) {|msg|
        record = get_class(rrtype, rrclass).decode_rdata(msg)
      }
      record.name = name
      record.ttl = ttl
      record.type = rrtype
      record.klass = rrclass        
      
      return record
    end
    
    #Return an array of all the currently implemented RR types
    def RR.implemented_rrs
      return ClassHash.keys.map {|k| Dnsruby::Types.to_string(k[0])}
    end
    
    private
    def RR._get_subclass(name, rrtype, rrclass, ttl, rdata) #:nodoc: all
      return unless (rrtype!=nil)        
      record = get_class(rrtype, rrclass).new(rdata)        
      record.name = name
      record.ttl = ttl
      record.type = rrtype
      record.klass = rrclass   
      return record
    end	
    public
    
    #Returns a string representation of the RR in zone file format
    def to_s
      return (@name?@name.to_s():"") + ".\t" +(@ttl?@ttl.to_s():"") + "\t" + (klass()?klass.to_s():"") + "\t" + (type()?type.to_s():"") + "\t" + rdata_to_string
    end
    
    #Get a string representation of the data section of the RR (in zone file format)
    def rdata_to_string
      if (@rdata && @rdata.length > 0)
        return @rdata
      else 
        return "no rdata"
      end
    end
    
    def from_data(data) #:nodoc: all
      # to be implemented by subclasses
      raise NotImplementedError.new
    end
    
    def from_string(input) #:nodoc: all
      # to be implemented by subclasses
      #      raise NotImplementedError.new
    end
    
    def encode_rdata(msg) #:nodoc: all
      # to be implemented by subclasses
      raise EncodeError.new("#{self.class} is RR.") 
    end
    
    def self.decode_rdata(msg) #:nodoc: all
      # to be implemented by subclasses
      raise DecodeError.new("#{self.class} is RR.") 
    end
    
    def ==(other)
      return false unless self.class == other.class
      s_ivars = self.instance_variables
      s_ivars.sort!
      s_ivars.delete "@ttl" # RFC 2136 section 1.1
      
      o_ivars = other.instance_variables
      o_ivars.sort!
      o_ivars.delete "@ttl" # RFC 2136 section 1.1
      
      return s_ivars == o_ivars &&
        s_ivars.collect {|name| self.instance_variable_get name} == 
        o_ivars.collect {|name| other.instance_variable_get name}
    end
    
    def eql?(other) #:nodoc:
      return self == other
    end
    
    def hash # :nodoc:
      h = 0      
      vars = self.instance_variables
      vars.delete "@ttl"
      vars.each {|name|
        h ^= self.instance_variable_get(name).hash
      }
      return h
    end
    
    #Get an RR of the specified type and class
    def self.get_class(type_value, class_value) #:nodoc: all
      #      if (type_value == Types.OPT)
      #        return Class.new(OPT)
      #      end
      if (type_value.class == Class)
        type_value = type_value.const_get(:TypeValue)
        return ClassHash[[type_value, Classes.to_code(class_value)]] ||
          Generic.create(type_value, Classes.to_code(class_value))
      else
        if (type_value.class == Types)
          type_value = type_value.code
        else
          type_value = Types.new(type_value).code
        end
        if (class_value.class == Classes)
          class_value = class_value.code
        else
          class_value = Classes.new(class_value).code
        end
        return ClassHash[[type_value, class_value]] ||
          Generic.create(type_value, class_value)
      end
      return ret
    end  
    
    
    #Create a new RR from the arguments, which can be either a String or a Hash.
    #See new_from_string and new_from_hash for details
    #
    #   a     = Dnsruby::RR.create("foo.example.com. 86400 A 10.1.2.3")
    #   mx    = Dnsruby::RR.create("example.com. 7200 MX 10 mailhost.example.com.")
    #   cname = Dnsruby::RR.create("www.example.com 300 IN CNAME www1.example.com")
    #   txt   = Dnsruby::RR.create('baz.example.com 3600 HS TXT "text record"')
    #   
    #   rr = Dnsruby::RR.create({:name => "example.com"})
    #   rr = Dnsruby::RR.create({:name => "example.com", :type => "MX", :ttl => 10, 
    #                                  :preference => 5, :exchange => "mx1.example.com"})
    #   
    def RR.create(*args)
      if (args.length == 1) && (args[0].class == String) 
        return new_from_string(args[0])
      elsif (args.length == 1) && (args[0].class == Hash) 
        return new_from_hash(args[0])
      else 
        return new_from_data(args)
      end
    end
    
  end
end  
require 'Dnsruby/resource/domain_name'
require 'Dnsruby/resource/generic'
require 'Dnsruby/resource/IN'
