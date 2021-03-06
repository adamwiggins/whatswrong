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
  #== Dnsruby::Name class
  #
  #A representation of a DNS name
  #(RFC1035, section 3.1)
  #
  #== methods
  #
  #* Name::create(namestring)
  #* Name#absolute?
  #* Name#wild?
  #* Name#subdomain_of?(other)
  #* Name#labels
  #
  class Name
    MaxNameLength=255
    #--
    # A Name is a collection of Labels. Each label is presentation-formatted
    # When a Name is wire-encoded, the label array is walked, and each label is wire-encoded.
    # When a Name is unencoded, each label is unencoded, and added to the Name collection of labels.
    # When a Name is made from a string, the Name is split into Labels.
    #++
    #Creates a new Dnsruby::Name from +arg+. +arg+ can be :
    #
    #* Name:: returns +arg+
    #* String:: returns a new Name
    def self.create(arg)
      case arg
      when Name
        return arg
      when String
#        arg.gsub!(/\.$/o, "")
        return Name.new(split_escaped(arg), /\.\z/ =~ arg ? true : false)
      when Array
        return Name.new(arg, /\.\z/ =~ ((arg.last.kind_of?String)?arg.last : arg.last.string) ? true : false)
      else        
        raise ArgumentError.new("cannot interpret as DNS name: #{arg.inspect}")
      end
    end
    
    def self.split_escaped(arg) #:nodoc: all
      encodedlabels = name2encodedlabels(arg)
      return encodedlabels2name(encodedlabels).labels
    end
    
    attr_reader :labels
    
    #This method should only be called internally.
    #Use Name::create to create a new Name
    def initialize(labels, absolute=true) #:nodoc: all
      total_length=labels.length-1
      labels.each do |l| 
        if (!l.kind_of?Label)
          raise ArgumentError.new("Name::new called with non-labels. Use Name::create instead?")
        end
        total_length+=l.length 
      end
      if (total_length > MaxNameLength) 
        raise ResolvError.new("Name length is #{total_length}, greater than max of #{MaxNameLength} octets!")
      end
      @labels = labels
      @absolute = absolute
    end
    
    def downcase
      labels = []
      @labels.each do |label| labels << Label.new(label.downcase) end
      return Name.create(labels)
    end
    
    def inspect # :nodoc:
      "#<#{self.class}: #{self.to_s}#{@absolute ? '.' : ''}>"
    end
    
    #Returns true if this Name is absolute
    def absolute?
      return @absolute
    end
    
    #Is this name a wildcard?
    def wild?
      if (labels.length == 0)
        return false
      end
      return (labels[0].string == '*')
    end
    
    def ==(other) # :nodoc:
      return false unless Name === other
      return @labels == other.labels && @absolute == other.absolute?
    end
    alias eql? == # :nodoc:
    
    # Tests subdomain-of relation : returns true if this name 
    # is a subdomain of +other+.
    #
    #   domain = Resolv::Name.create("y.z")
    #   p Resolv::Name.create("w.x.y.z").subdomain_of?(domain) #=> true
    #   p Resolv::Name.create("x.y.z").subdomain_of?(domain) #=> true
    #   p Resolv::Name.create("y.z").subdomain_of?(domain) #=> false
    #   p Resolv::Name.create("z").subdomain_of?(domain) #=> false
    #   p Resolv::Name.create("x.y.z.").subdomain_of?(domain) #=> false
    #   p Resolv::Name.create("w.z").subdomain_of?(domain) #=> false
    #
    def subdomain_of?(other)
      raise ArgumentError, "not a domain name: #{other.inspect}" unless Name === other
      return false if @absolute != other.absolute?
      other_len = other.length
      return false if @labels.length <= other_len
      return @labels[-other_len, other_len] == other.to_a
    end
    
    def hash # :nodoc:
      return @labels.hash ^ @absolute.hash
    end
    
    def to_a #:nodoc: all
      return @labels
    end
    
    def length #:nodoc: all
      return @labels.length
    end
    
    def [](i) #:nodoc: all
      return @labels[i]
    end
    
    # returns the domain name as a string.
    #
    # The domain name doesn't have a trailing dot even if the name object is
    # absolute.
    # 
    # Example : 
    #
    #   p Resolv::Name.create("x.y.z.").to_s #=> "x.y.z"
    #   p Resolv::Name.create("x.y.z").to_s #=> "x.y.z"
    #
    def to_s
      return @labels.collect{|l| (l.kind_of?String) ? l : l.string}.join('.')
      
    end
    
    # Utility function
    #
    # name2labels to translate names from presentation format into an
    # array of "wire-format" labels.        
    # in: dName a string with a domain name in presentation format (1035
    # sect 5.1)
    # out: an array of labels in wire format.        
    def self.name2encodedlabels (dName) #:nodoc: all
      names=[]
      j=0;
      while (dName && dName.length > 0)
        names[j],dName = encode(dName)
        j+=1
      end
      
      return names
    end
    
    def self.encodedlabels2name(labels) #:nodoc: all
      ls = []
      labels.each do |l|
        ls.push(Name.decode(l.string))
      end
      return Name.new(ls)
    end    
    
    def self.decode(wire) #:nodoc: all
      presentation=""
      length=wire.length
      # There must be a nice regexp to do this.. but since I failed to
      # find one I scan the name string until I find a '\', at that time
      # I start looking forward and do the magic.
      
      i=0;
      
      while (i < length )
        c=wire.unpack("x#{i}C1") [0]
        if ( c < 33 || c > 126 )
          presentation=presentation + sprintf("\\%03u" ,c)
        elsif ( c.chr ==  "\"" )
          presentation=presentation +  "\\\""
        elsif ( c.chr ==  "\$")
          presentation=presentation +  "\\\$"
        elsif ( c.chr == "(" )
          presentation=presentation + "\\("
        elsif ( c.chr == ")" )
          presentation=presentation +  "\\)"
        elsif ( c.chr == ";" )
          presentation=presentation +  "\\;"
        elsif ( c.chr == "@" )
          presentation=presentation +  "\\@"
        elsif ( c.chr == "\\" )
          presentation=presentation + "\\\\" 
        elsif ( c.chr == ".")
          presentation=presentation +  "\\."
        else
          presentation=presentation + c.chr()
        end
        i=i+1
      end
      
      return Label.new(presentation)
    end
    
    
    
    # wire,leftover=presentation2wire(leftover)    
    # Will parse the input presentation format and return everything before
    # the first non-escaped "." in the first element of the return array and
    # all that has not been parsed yet in the 2nd argument.        
    def self.encode(presentation) #:nodoc: all
      presentation=presentation.to_s
      wire="";
      length=presentation.length;
      
      i=0;
      
      while (i < length )
        c=presentation.unpack("x#{i}C1") [0]
        if (c == 46) # ord('.')
          endstring = presentation[i+1, presentation.length-(i+1)]
          return Label.new(wire),endstring
        end
        if (c == 92) # ord'\\'
          #backslash found
          pos = i+1
          # pos sets where next pattern matching should start
          if (presentation.index(/\G(\d\d\d)/o, pos))
            wire=wire+[$1.to_i].pack("C")
            i=i+3
          elsif(presentation.index(/\Gx([0..9a..fA..F][0..9a..fA..F])/o, pos))
            wire=wire+[$1].pack("H*")
            i=i+3
          elsif(presentation.index(/\G\./o, pos))
            wire=wire+"\."
            i=i+1
          elsif(presentation.index(/\G@/o,pos))
            wire=wire+"@"
            i=i+1
          elsif(presentation.index(/\G\(/o, pos))
            wire=wire+"("
            i=i+1
          elsif(presentation.index(/\G\)/o, pos))
            wire=wire+")"
            i=i+1
          elsif(presentation.index(/\G\\/o, pos))
            wire=wire+"\\"
            i+=1
          end
        else
          wire = wire + [c].pack("C")
        end
        i=i+1
      end
      
      return Label.new(wire)
    end
    
    #  end
    
    
    #== Dnsruby::Label class
    #
    #(RFC1035, section 3.1)
    #
    class Label
      MaxLabelLength = 63
      @@max_length=MaxLabelLength
      # Split a Name into its component Labels
      def self.split(arg)
        labels = []
        #        arg.scan(/[^\.]+/) {labels << Str.new($&)}
        arg.scan(/[^\.]+/) {labels << new($&)}
        return labels
      end
      
      def self.set_max_length(l)
        @@max_length=l
      end
      
      def initialize(string)
        if (string.length > @@max_length)
          raise ResolvError.new("Label too long (#{string.length}, max length=#{MaxLabelLength}). Label = #{string}")
        end
        @downcase = string.downcase
        @string = string
      end
      attr_reader :string, :downcase
      
      def to_s
        return @string.to_s # + "."
      end
      
      def length
        return @string.length
      end
      
      def inspect
        return "#<#{self.class} #{self.to_s}>"
      end
      
      def ==(other)
        return @downcase == other.downcase
      end
      
      def eql?(other)
        return self == other
      end
      
      def hash
        return @downcase.hash
      end
    end
  end
end