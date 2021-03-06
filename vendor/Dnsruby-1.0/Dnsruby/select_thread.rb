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
require 'socket'
#require 'thread'
begin
  require 'fastthread'
rescue LoadError
  require 'thread'
end
require 'singleton'
module Dnsruby
  Thread::abort_on_exception = true
  class SelectThread #:nodoc: all
    class SelectWakeup < RuntimeError; end
    include Singleton
    # This singleton class runs a continuous select loop which 
    # listens for responses on all of the in-use sockets.
    # When a new query is sent, the thread is woken up, and
    # the socket is added to the select loop (and the new timeout
    # calculated).
    # Note that a combination of the socket and the packet ID is
    # sufficient to uniquely identify the query to the select thread.
    # But how do we identify it to the client thread?
    # Push [id, response] onto the response queue?
    # Or [id, timeout]
    # 
    # But how do we find the response queue for a particular query?
    # Hash of client_id->[query, client_queue, socket]
    # and socket->[client_id]
    # 
    # @todo@ should we implement some of cancel function?
    
    def initialize
      @@mutex = Mutex.new
      @@mutex.synchronize {
        @@in_select=false
        #        @@notifier,@@notified=IO.pipe
        @@sockets = [] # @@notified]
        @@timeouts = Hash.new
        #    @@mutex.synchronize do
        @@query_hash = Hash.new
        @@socket_hash = Hash.new
        @@observers = Hash.new
        @@tick_observers = []
        @@queued_exceptions=[]
        #    end
        # Now start the select thread
        @@select_thread = Thread.new {
          do_select
        }
      }
    end
    
    class QuerySettings
      attr_accessor :query_bytes, :query, :ignore_truncation, :client_queue, 
        :client_query_id, :socket, :dest_server, :dest_port, :endtime, :udp_packet_size,
        :single_resolver
      # new(query_bytes, query, ignore_truncation, client_queue, client_query_id,
      #     socket, dest_server, dest_port, endtime, , udp_packet_size, single_resolver)
      def initialize(*args)
        @query_bytes = args[0]
        @query = args[1]
        @ignore_truncation=args[2]
        @client_queue = args[3]
        @client_query_id = args[4]
        @socket = args[5]
        @dest_server = args[6]
        @dest_port=args[7]
        @endtime = args[8]  
        @udp_packet_size = args[9]
        @single_resolver = args[10]
      end
    end
    
    def add_to_select(query_settings)
      # Add the query to sockets, and then wake the select thread up
      @@mutex.synchronize {
        check_select_thread_synchronized
        # @TODO@ This assumes that all client_query_ids are unique!
        # Would be a good idea at least to check this...
        @@query_hash[query_settings.client_query_id]=query_settings
        @@socket_hash[query_settings.socket]=[query_settings.client_query_id] # @todo@ If we use persistent sockets then we need to update this array
        @@timeouts[query_settings.client_query_id]=query_settings.endtime
        @@sockets.push(query_settings.socket)
      }
    end
    
    def check_select_thread_synchronized
      if (!@@select_thread.alive?)
        TheLog.debug("Restarting select thread")
        @@select_thread = Thread.new {
          do_select
        }
      end
    end
    
    def select_thread_alive?
      ret=true
      @@mutex.synchronize{
        ret = @@select_thread.alive?
      }
      return ret
    end
    
    def do_select
      unused_loop_count = 0
      while true do
        send_tick_to_observers
        send_queued_exceptions
        timeout = tick_time = (Time.now+0.1) - Time.now # We provide a timer service to various Dnsruby classes
        sockets=[]
        timeouts=[]
        has_observer = false
        @@mutex.synchronize {                
          sockets = @@sockets 
          timeouts = @@timeouts.values
          has_observer = !@@observers.empty?
        }
        if (timeouts.length > 0)
          timeouts.sort!
          timeout = timeouts[0] - Time.now
          if (timeout <= 0)
            process_timeouts
            timeout = 0
            next
          end
        end
        ready=nil
        if (has_observer && (timeout > tick_time))
          timeout = tick_time
        end
        begin
          ready, write, errors = IO.select(sockets, nil, nil, timeout)
        rescue SelectWakeup
          # If SelectWakeup, then just restart this loop - the select call will be made with the new data
          next
        end
        if (ready == nil)
          # proces the timeouts
          process_timeouts
          unused_loop_count+=1
        else
          process_ready(ready)
          unused_loop_count=0
          #                  process_error(errors)
        end
        @@mutex.synchronize{
          if (unused_loop_count > 10 && @@query_hash.empty? && @@observers.empty?)
            TheLog.debug("Stopping select loop")
            return
          end
        }
        #              }
      end
    end
    
    def process_error(errors)
      TheLog.debug("Error! #{errors.inspect}")
      # @todo@ Process errors [can we do this in single socket environment?]
    end
    
#        @@query_hash[query_settings.client_query_id]=query_settings
#        @@socket_hash[query_settings.socket]=[query_settings.client_query_id] # @todo@ If we use persistent sockets then we need to update this array
    def process_ready(ready)
      ready.each do |socket|
        query_settings = nil
        @@mutex.synchronize{
          # Can do this if we have a query per socket, but not otherwise...
          c_q_id = @@socket_hash[socket][0] # @todo@ If we use persistent sockets then this won't work
          query_settings = @@query_hash[c_q_id]
        }
        udp_packet_size = query_settings.udp_packet_size
        msg, bytes = get_incoming_data(socket, udp_packet_size)
        if (msg!=nil)
          send_response_to_client(msg, bytes, socket)
        end
        ready.delete(socket)
      end
    end
    
    def send_response_to_client(msg, bytes, socket)
      # Figure out which client_ids we were expecting on this socket, then see if any header ids match up
      client_ids=[]
      @@mutex.synchronize{
        client_ids = @@socket_hash[socket]
      }
      # get the queries associated with them
      client_ids.each do |id|
        query_header_id=nil
        @@mutex.synchronize{
          query_header_id = @@query_hash[id].query.header.id
        }
        if (query_header_id == msg.header.id)
          # process the response
          client_queue = nil
          res = nil
          query=nil
          @@mutex.synchronize{
            client_queue = @@query_hash[id].client_queue
            res = @@query_hash[id].single_resolver
            query = @@query_hash[id].query
          }
          tcp = (socket.class == TCPSocket)
          # At this point, we should check if the response is OK
          if (res.check_response(msg, bytes, query, client_queue, id, tcp))
            remove_id(id)
            exception = msg.header.get_exception
            TheLog.debug("Pushing response to client queue")
            client_queue.push([id, msg, exception])
            notify_queue_observers(client_queue, id)
          else
            # Sending query again - don't return response
          end
          return
        end
      end
      # If not, then we have an error
      TheLog.error("Stray packet - " + msg.inspect + "\n from " + socket.inspect)
    end
    
    def remove_id(id)
      socket=nil
      @@mutex.synchronize{
        socket = @@query_hash[id].socket
        @@timeouts.delete(id)
        @@query_hash.delete(id)      
        @@sockets.delete(socket) # @TODO@ Not if persistent!
      }
      TheLog.debug("Closing socket #{socket}")
      socket.close # @TODO@ Not if persistent!
    end
    
    def process_timeouts
      time_now = Time.now
      timeouts={}
      @@mutex.synchronize {
        timeouts = @@timeouts
      }
      timeouts.each do |client_id, timeout|
        if (timeout < time_now)
          send_exception_to_client(ResolvTimeout.new("Query timed out"), nil, client_id)
        end
      end
    end
    
    def tcp_read(socket, len)
      buf=""
      while (buf.length < len) do
        buf += socket.recv(len-buf.length)
      end
      return buf
    end
    
    def get_incoming_data(socket, packet_size)
      answerfrom,answerip,answerport,answersize=nil
      ans,buf = nil
      begin
        if (socket.class == TCPSocket)
          # @todo@ Ruby Bug #9061 stops this working right
          # We'd like to do a socket.recvfrom, but that raises an Exception
          # on Windows for TCPSocket for Ruby 1.8.5 (and 1.8.6).
          # So, we need to do something different for TCP than UDP. *sigh*
          # @TODO@ This workaround will only work if there is exactly one socket per query
          #    - *not* ideal TCP use!
          @@mutex.synchronize{
            client_id = @@socket_hash[socket][0]
            answerfrom = @@query_hash[client_id].dest_server
            answerip = answerfrom
            answerport = @@query_hash[client_id].dest_port
          }
          buf = tcp_read(socket, 2)
          answersize = buf.unpack('n')[0]
          buf = tcp_read(socket,answersize)
        else
          if (ret = socket.recvfrom(packet_size))
            buf = ret[0]
            answerport=ret[1][1]
            answerfrom=ret[1][2]
            answerip=ret[1][3]
            answersize=(buf.length)
          else
            # recvfrom failed - why?
            TheLog.error("Error - recvfrom failed from #{socket}")
            handle_recvfrom_failure(socket)          
            return
          end        
        end
      rescue Exception => e
        TheLog.error("Error - recvfrom failed from #{socket}, exception : #{e}")
        handle_recvfrom_failure(socket)          
        return
      end
      TheLog.debug(";; answer from #{answerfrom} : #{answersize} bytes\n")
      
      begin
        ans = Message.decode(buf)
      rescue Exception => e
        TheLog.error("Decode error! #{e.class}, #{e}\nfor msg (length=#{buf.length}) : #{buf}")
        client_id=get_client_id_from_answerfrom(socket, answerip, answerport)
        if (client_id != nil) 
          send_exception_to_client(e, socket, client_id)
        else
          TheLog.error("Decode error from #{answerfrom} but can't determine packet id")
        end
        return
      end
      
      if (ans!= nil)
        TheLog.debug("#{ans}")
        ans.answerfrom=(answerfrom)
        ans.answersize=(answersize)
      end
      return ans, buf
    end
    
    def handle_recvfrom_failure(socket)
      #  @TODO@ No way to notify the client about this error, unless there was only one connection on the socket
      ids_for_socket = []
      @@mutex.synchronize{
        ids_for_socket = @@socket_hash[socket]
      }
      if (ids_for_socket.length == 1)
        answerfrom=nil
        @@mutex.synchronize{
          query_settings = @@query_hash[ids_for_socket[0]]
          answerfrom=query_settings.dest_server
        }
        send_exception_to_client(OtherResolvError.new("recvfrom failed from #{answerfrom}"), socket, ids_for_socket[0])
      else
        TheLog.fatal("Recvfrom failed from #{socket}, no way to tell query id")
      end
    end
    
    def get_client_id_from_answerfrom(socket, answerip, answerport)
      client_id=nil
      # Figure out client id from answerfrom
      @@mutex.synchronize{
        ids = @@socket_hash[socket]
        ids.each do |id|
          # Does this id speak to this dest_server?
          query_settings = @@query_hash[id]
          if (answerip == query_settings.dest_server && answerport == query_settings.dest_port)
            # We have a match
            # - @TODO@ as long as we're not speaking to the same server on two ports!
            client_id = id
            break
          end
        end
      }
      return client_id
    end
    
    def send_exception_to_client(err, socket, client_id, msg=nil)
      # find the client response queue
      client_queue = nil
      @@mutex.synchronize {
        client_queue = @@query_hash[client_id].client_queue
      }
      remove_id(client_id)
      push_exception_to_client(client_id, client_queue, err, msg)
    end
    
    def push_exception_to_select(client_id, client_queue, err, msg)
      @@mutex.synchronize{
        @@queued_exceptions.push([client_id, client_queue, err, msg])
      }
    end
    
    def send_queued_exceptions
      exceptions = []
      @@mutex.synchronize{
        exceptions = @@queued_exceptions
        @@queued_exceptions = []
      }
      
      exceptions.each do |item|
        client_id, client_queue, err, msg = item
        push_exception_to_client(client_id, client_queue, err, msg)
      end
    end
    
    def push_exception_to_client(client_id, client_queue, err, msg)
      # Now push the exception on the queue
      client_queue.push([client_id, msg, err])
      notify_queue_observers(client_queue, client_id)
    end
    
    def add_observer(client_queue, observer)
      @@mutex.synchronize {
        @@observers[client_queue]=observer
        check_select_thread_synchronized # Is this really necessary? The client should start the thread by sending a query, really...        
        if (!@@tick_observers.include?observer)
          @@tick_observers.push(observer)
        end
      }
    end
    
    def remove_observer(client_queue, observer)
      @@mutex.synchronize {
        if (@@observers[client_queue]==observer)
          @@observers.delete(observer)
        else
          TheLog.error("remove_observer called with wrong observer for queue")
          raise ArgumentError.new("remove_observer called with wrong observer for queue")
        end
        if (!@@observers.values.include?observer)
          @@tick_observers.delete(observer)
        end
      }
    end
    
    def notify_queue_observers(client_queue, client_query_id)
      # If any observers are known for this query queue then notify them
      observer=nil
      @@mutex.synchronize {
        observer = @@observers[client_queue]
      }
      if (observer)
        observer.handle_queue_event(client_queue, client_query_id)
      end      
    end
    
    def send_tick_to_observers
      # If any observers are known then send them a tick
      tick_observers=nil
      @@mutex.synchronize {
        tick_observers = @@tick_observers
      }
      tick_observers.each do |observer|
        observer.tick
      end
    end
  end
end