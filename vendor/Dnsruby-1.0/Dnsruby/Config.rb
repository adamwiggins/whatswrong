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
  #== Description
  # The Config class determines the system configuration for DNS.
  # In particular, it determines the nameserver to target queries to.
  #
  #
  # It also specifies whether and how the search list and default 
  # domain should be applied to queries, according to the following
  # algorithm :
  # 
  #*     If the name is absolute, then it is used as is.
  # 
  #*     If the name is not absolute, then :
  #     
  #         If apply_domain is true, and ndots is greater than the number 
  #         of labels in the name, then the default domain is added to the name.
  #         
  #         If apply_search_list is true, then each member of the search list
  #         is appended to the name.
  #
  class Config
    #--
    #@TODO@ Switches for :
    #
    #  -- single socket for all packets
    #  -- single new socket for individual client queries (including retries and multiple nameservers)
    #++
    
    # The list of nameservers to query
    attr_reader :nameserver
    # Should the search list be applied?
    attr_accessor :apply_search_list
    # Should the default domain be applied?
    attr_accessor :apply_domain
    # The minimum number of labels in the query name (if it is not absolute) before it is considered complete
    attr_reader :ndots
    
    # Set the config. Parameter can be :
    # 
    # * A String containing the name of the config file to load 
    #        e.g. /etc/resolv.conf
    # 
    # * A hash with the following elements : 
    #        nameserver (String)
    #        domain (String)
    #        search (String)
    #        ndots (Fixnum)
    #
    # This method should not normally be called by client code.
    def set_config_info(config_info)
      parse_config(config_info)
    end
    
    # Create a new Config with system default values  
    def initialize()
      @mutex = Mutex.new
      parse_config
    end
    # Reset the config to default values    
    def Config.reset
      c = Config.new
      c.parse_config
    end
    
    def parse_config(config_info=nil) #:nodoc: all
      @mutex.synchronize {
        ns = []
        @nameserver = []
        @domain, s, @search = nil
        dom=""
        nd = 1
        @ndots = 1
        @apply_search_list = true
        @apply_domain = true
        config_hash = Config.default_config_hash
        case config_info
        when nil
        when String
          config_hash.merge!(Config.parse_resolv_conf(config_info))
        when Hash
          config_hash.merge!(config_info.dup)
          if String === config_hash[:nameserver]
            config_hash[:nameserver] = [config_hash[:nameserver]]
          end
          if String === config_hash[:search]
            config_hash[:search] = [config_hash[:search]]
          end
        else
          raise ArgumentError.new("invalid resolv configuration: #{@config_info.inspect}")
        end
        ns = config_hash[:nameserver] if config_hash.include? :nameserver
        s = config_hash[:search] if config_hash.include? :search
        nd = config_hash[:ndots] if config_hash.include? :ndots
        @apply_search_list = config_hash[:apply_search_list] if config_hash.include? :apply_search_list
        @apply_domain= config_hash[:apply_domain] if config_hash.include? :apply_domain
        dom = config_hash[:domain] if config_hash.include? :domain
        
        send("nameserver=",ns)        
        send("search=",s)        
        send("ndots=",nd)
        send("domain=",dom)        
      }
      TheLog.info(to_s)
    end
    
    # Set the default domain
    def domain=(dom)
      if (dom)
        if !dom.kind_of?(String)
          raise ArgumentError.new("invalid domain config: #{@domain.inspect}")
        end
        @domain = Name::Label.split(dom)
      else
        @domain=nil
      end
    end
    
    # Set ndots
    def ndots=(nd)
      @ndots=nd
      if !@ndots.kind_of?(Integer)
        raise ArgumentError.new("invalid ndots config: #{@ndots.inspect}")
      end
    end
    
    # Set the default search path
    def search=(s)
      @search=s
      if @search
        if @search.class == Array
          @search = @search.map {|arg| Name::Label.split(arg) }
        else
          raise ArgumentError.new("invalid search config: search must be an array!")
        end
      else
        hostname = Socket.gethostname
        if /\./ =~ hostname
          @search = [Name::Label.split($')]
        else
          @search = [[]]
        end
      end
      
      if !@search.kind_of?(Array) ||
          #              !@search.all? {|ls| ls.all? {|l| Label::Str === l } }
        !@search.all? {|ls| ls.all? {|l| Name::Label === l } }
        raise ArgumentError.new("invalid search config: #{@search.inspect}")
      end
    end
    
    def check_ns(ns) #:nodoc: all
      if !ns.kind_of?(Array) ||
          !ns.all? {|n| (String === n || IPv4 === n || IPv6 === n)}
        raise ArgumentError.new("invalid nameserver config: #{ns.inspect}")
      end    
      ns.each_index do |i|
        ns[i]=Config.resolve_server(ns[i])
      end
    end
    
    # Add a nameserver to the list of nameservers.
    # 
    # Can take either a single String or an array of Strings.
    # The new nameservers are added at a higher priority.
    def add_nameserver(ns)
      if (ns.kind_of?String) 
        ns=[ns]
      end
      check_ns(ns)
      ns.reverse_each do |n|
        if (!@nameserver.include?(n))
          self.nameserver=[n]+@nameserver
        end
      end
    end
    
    # Set the config to point to a single nameserver
    def nameserver=(ns)
      check_ns(ns)
      #      @nameserver = ['0.0.0.0'] if (@nameserver.class != Array || @nameserver.empty?)
      # Now go through and ensure that all ns point to IP addresses, not domain names
      @nameserver=ns
      TheLog.debug("Nameservers = #{@nameserver.join(", ")}")
    end
    
    def Config.resolve_server(ns) #:nodoc: all
      # Sanity check server
      # If it's an IP address, then use that for server
      # If it's a name, then we'll need to resolve it first
      server=ns
      begin
        addr = IPv4.create(ns)
        server = ns
      rescue Exception 
        begin
          addr=IPv6.create(ns)
          server = ns
        rescue Exception
          begin
            # try to resolve server to address
            addr = TCPSocket.gethostbyname(ns)[3] # @TODO@ Replace this with Dnsruby call when lookups work
            server = addr
          rescue Exception => e
            TheLog.error("Can't make sense of nameserver : #{server}, exception : #{e}")
            raise ArgumentError.new("Can't make sense of nameserver : #{server}, exception : #{e}")
          end
        end
      end
      return server
    end
    
    def Config.parse_resolv_conf(filename) #:nodoc: all
      nameserver = []
      search = nil
      domain = nil
      ndots = 1
      open(filename) {|f|
        f.each {|line|
          line.sub!(/[#;].*/, '')
          keyword, *args = line.split(/\s+/)
          args.each { |arg|
            arg.untaint
          }
          next unless keyword
          case keyword
          when 'nameserver'
            nameserver += args
          when 'domain'
            next if args.empty?
            domain = args[0]
            #            if search == nil
            #              search = []
            #            end
            #            search.push(args[0])
          when 'search'
            next if args.empty?
            if search == nil
              search = []
            end
            args.each {|a| search.push(a)}
          when 'options'
            args.each {|arg|
              case arg
              when /\Andots:(\d+)\z/
                ndots = $1.to_i
              end
            }
          end
        }
      }
      return { :nameserver => nameserver, :domain => domain, :search => search, :ndots => ndots }
    end
    
    def inspect #:nodoc: all
      to_s
    end
    
    def to_s
      ret = "Config - nameservers : "
      @nameserver.each {|n| ret += n.to_s + ", "}
      domain_string="empty"
      if (@domain!=nil)
        domain_string=@domain.to_s
      end
      ret += " domain : #{domain_string}, search : "
      search.each {|s| ret += s + ", " }
      ret += " ndots : #{@ndots}"
      return ret
    end
    
    def Config.default_config_hash(filename="/etc/resolv.conf") #:nodoc: all
      config_hash={}
      if File.exist? filename
        config_hash = Config.parse_resolv_conf(filename)
      else
        if (/java/ =~ RUBY_PLATFORM && !(filename=~/:/))
          # Problem with paths and Windows on JRuby - see if we can munge the drive...
          wd = Dir.getwd
          drive = wd.split(':')[0]
          if (drive.length==1)
            file = drive << ":" << filename
            if File.exist? file
              config_hash = Config.parse_resolv_conf(file)
            end
          end
        elsif /mswin32|cygwin|mingw|bccwin/ =~ RUBY_PLATFORM
          # @TODO@ Need to get windows domain sorted
          search, nameserver = Win32::Resolv.get_resolv_info
          #          config_hash[:domain] = domain if domain
          config_hash[:nameserver] = nameserver if nameserver
          config_hash[:search] = [search].flatten if search
        end
      end
      config_hash
    end
    
    # Return the search path
    def search
      search = []
      @search.each do |s|
        search.push(Name.new(s).to_s)
      end
      return search
    end
    
    # Return the default domain
    def domain
      if (@domain==nil)
        return nil
      end
      return Name.create(@domain).to_s
    end
    
    def single? #:nodoc: all
      if @nameserver.length == 1
        return @nameserver[0]
      else
        return nil
      end
    end
    
    def generate_candidates(name) #:nodoc: all
      candidates = []
      name = Name.create(name)
      if name.absolute?
        candidates = [name]
      else
        if (@apply_domain)
          if @ndots > name.length - 1
            candidates.push(Name.create(name.to_a+@domain))
          end
        end
        if (!@apply_search_list)
          candidates.push(Name.create(name.to_a))
        else
          if @ndots <= name.length - 1
            candidates.push(Name.create(name.to_a))
          end
          candidates.concat(@search.map {|domain| Name.create(name.to_a + domain)})
          if (name.length == 1)
            candidates.concat([Name.create(name.to_a)])
          end
        end          
      end
      return candidates
    end
  end
end