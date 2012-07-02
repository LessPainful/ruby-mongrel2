#!/usr/bin/ruby

require 'socket'
require 'zmq'
require 'yajl'
require 'digest/sha1'
require 'loggability'

require 'mongrel2' unless defined?( Mongrel2 )


# The Mongrel2 connection class. Connection objects serve as a front end for 
# the ZMQ sockets which talk to the mongrel2 server/s for your handler. It receives 
# TNetString requests and wraps Mongrel2::Request objects around them, and
# then encodes and sends Mongrel2::Response objects back to the server.
#
# == References
# * http://mongrel2.org/static/book-finalch6.html#x8-710005.3
class Mongrel2::Connection
	extend Loggability

	# Loggability API -- set up logging under the 'mongrel2' log host
	log_to :mongrel2


	### Create a new Connection identified by +app_id+ (a UUID or other unique string) that
	### will connect to a Mongrel2 server on the +sub_addr+ and +pub_addr+ (e.g., 
	### 'tcp://127.0.0.1:9998').
	def initialize( app_id, sub_addr, pub_addr )
		@app_id       = app_id
		@sub_addr     = sub_addr
		@pub_addr     = pub_addr

		@request_sock = @response_sock = nil

		@identifier   = make_identifier( app_id )
		@closed       = false
	end


	### Copy constructor -- don't keep the +original+'s sockets or closed state.
	def initialize_copy( original )
		@request_sock = @response_sock = nil
		@closed = false
	end



	######
	public
	######

	# The application's identifier string that associates it with its route
	attr_reader :app_id

	# The ZMQ socket identity used by this connection
	attr_reader :identifier

	# The connection's subscription (request) socket address
	attr_reader :sub_addr

	# The connection's publication (response) socket address
	attr_reader :pub_addr


	### Establish both connections to the Mongrel2 server.
	def connect
		ctx = Mongrel2.zmq_context
		self.log.debug "0mq Context is: %p" % [ ctx ]

		self.log.info "Connecting PULL request socket (%s)" % [ self.sub_addr ]
		@request_sock  = ctx.socket( ZMQ::PULL )
		@request_sock.setsockopt( ZMQ::LINGER, 0 )
		@request_sock.connect( self.sub_addr )

		self.log.info "Connecting PUB response socket (%s)" % [ self.pub_addr ]
		@response_sock  = ctx.socket( ZMQ::PUB )
		@response_sock.setsockopt( ZMQ::IDENTITY, self.identifier )
		@response_sock.setsockopt( ZMQ::LINGER, 0 )
		@response_sock.connect( self.pub_addr )
	end


	### Fetch the ZMQ::PULL socket for incoming requests, establishing the
	### connection to Mongrel if it hasn't been already.
	def request_sock
		self.check_closed
		self.connect unless @request_sock
		return @request_sock
	end


	### Fetch the ZMQ::PUB socket for outgoing responses, establishing the
	### connection to Mongrel if it hasn't been already.
	def response_sock
		self.check_closed
		self.connect unless @response_sock
		return @response_sock
	end


	### Fetch the next request from the server as raw TNetString data.
	def recv
		self.check_closed

		self.log.debug "Fetching next request (PULL)"
		data = self.request_sock.recv
		self.log.debug "  got %s request data: %p" % [ data.encoding.name, data ]
		return data
	end


	### Fetch the next request from the server as a Mongrel2::Request object.
	def receive
		raw_req = self.recv
		self.log.debug "Receive: parsing raw request: %d bytes" % [ raw_req.bytesize ]
		return Mongrel2::Request.parse( raw_req )
	end


	### Write raw +data+ to the given connection ID (+conn_id+) at the given +sender_id+.
	def send( sender_id, conn_id, data )
		self.check_closed
		header = "%s %d:%s," % [ sender_id, conn_id.to_s.length, conn_id ]
		buf = header + ' ' + data
		self.log.debug "Sending response (PUB): %p" % [ buf ]
		self.response_sock.send( buf )
		self.log.debug "  done with send (%d bytes)" % [ buf.bytesize ]
	end


	### Write the specified +response+ (Mongrel::Response object) to the requester.
	def reply( response )
		response.each_chunk do |data|
			self.send( response.sender_id, response.conn_id, data )
		end
	end


	### Send the given +data+ to one or more connected clients identified by +client_ids+
	### via the server specified by +sender_id+. The +client_ids+ should be an Array of
	### Integer IDs no longer than Mongrel2::MAX_IDENTS.
	def broadcast( sender_id, conn_ids, data )
		idlist = conn_ids.flatten.map( &:to_s ).join( ' ' )
		self.send( sender_id, idlist, data )
	end


	### Tell the server to close the connection associated with the given +sender_id+ and
	### +conn_id+.
	def send_close( sender_id, conn_id )
		self.log.info "Sending kill message to connection %d" % [ conn_id ]
		self.send( sender_id, conn_id, '' )
	end


	### Tell the server to close the connection associated with the given +request_or_response+.
	def reply_close( request_or_response )
		self.send_close( request_or_response.sender_id, request_or_response.conn_id )
	end


	### Tell the server associated with +sender_id+ to close the connections associated 
	### with +conn_ids+.
	def broadcast_close( sender_id, *conn_ids )
		self.broadcast( sender_id, conn_ids.flatten, '' )
	end


	### Close both of the sockets and mark the Connection as closed.
	def close
		return if self.closed?
		self.closed = true
		@request_sock.close if @request_sock
		@response_sock.close if @response_sock
	end


	### Returns +true+ if the connection to the Mongrel2 server has been closed.
	def closed?
		return @closed
	end


	### Return a string describing the connection.
	def to_s
		return "{%s} %s <-> %s" % [
			self.app_id,
			self.sub_addr,
			self.pub_addr,
		]
	end

	### Returns a string containing a human-readable representation of the Connection,
	### suitable for debugging.
	def inspect
		state = if @request_sock
			if self.closed?
				"closed"
			else
				"connected"
			end
		else
			"not connected"
		end

		return "#<%p:0x%016x %s (%s)>" % [
			self.class,
			self.object_id * 2,
			self.to_s,
			state,
		]
	end



	#########
	protected
	#########

	# True if the Connection to the Mongrel2 server has been closed.
	attr_writer :closed


	### Check to be sure the Connection hasn't been closed, raising a Mongrel2::ConnectionError
	### if it has.
	def check_closed
		raise Mongrel2::ConnectionError, "operation on closed Connection" if self.closed?
	end


	#######
	private
	#######

	### Make a unique identifier for this connection's socket based on the +app_id+
	### and some other stuff.
	def make_identifier( app_id )
		identifier = Digest::SHA1.new
		identifier << app_id
		identifier << Socket.gethostname
		identifier << Process.pid.to_s
		identifier << Time.now.to_s

		return identifier.hexdigest
	end

end # class Mongrel2::Connection

# vim: set nosta noet ts=4 sw=4:

