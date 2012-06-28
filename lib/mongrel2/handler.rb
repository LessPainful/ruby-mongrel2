#!/usr/bin/env ruby

require 'zmq'
require 'loggability'

require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/config'

require 'mongrel2/request'
require 'mongrel2/httprequest'
require 'mongrel2/jsonrequest'
require 'mongrel2/xmlrequest'
require 'mongrel2/websocket'

# Mongrel2 Handler application class. Instances of this class are the applications
# which connection to one or more Mongrel2 routes and respond to requests.
#
# == Example
#
# A dumb, dead-simple example that just returns a plaintext 'Hello'
# document with a timestamp.
#
#     #!/usr/bin/env ruby
#
#     require 'mongrel2/handler'
#
#     class HelloWorldHandler < Mongrel2::Handler
#
#       ### The main method to override -- accepts requests and
#       ### returns responses.
#       def handle( request )
#           response = request.response
#
#           response.status = 200
#           response.headers.content_type = 'text/plain'
#           response.puts "Hello, world, it's #{Time.now}!"
#
#           return response
#       end
#
#     end # class HelloWorldHandler
#
#     HelloWorldHandler.run( 'helloworld-handler' )
#
# This assumes the Mongrel2 SQLite config database is in the current
# directory, and is named 'config.sqlite' (the Mongrel2 default), but
# if it's somewhere else, you can point the Mongrel2::Config class
# to it:
#
#     require 'mongrel2/config'
#     Mongrel2::Config.configure( :configdb => 'mongrel2.db' )
#
# Mongrel2 also includes support for Configurability, so you can
# configure it along with your database connection, etc. Just add a
# 'mongrel2' section to the config with a 'configdb' key that points
# to where the Mongrel2 SQLite config database lives:
#
#     # config.yaml
#     db:
#       uri: postgres://www@localhost/db01
#
#     mongrel2:
#       configdb: mongrel2.db
#
#     whatever_else:
#       ...
#
# Now just loading and installing the config configures Mongrel2 as
# well:
#
#     require 'configurability/config'
#
#     config = Configurability::Config.load( 'config.yml' )
#     config.install
#
# If the Mongrel2 config database isn't accessible, or you need to
# configure the Handler's two 0mq connections yourself for some
# reason, you can do that, too:
#
#     app = HelloWorldHandler.new( 'helloworld-handler',
#         'tcp://otherhost:9999', 'tcp://otherhost:9998' )
#     app.run
#
class Mongrel2::Handler
	extend Loggability
	include Mongrel2::Constants


	# Loggability API -- set up logging under the 'mongrel2' log host
	log_to :mongrel2


	### Create an instance of the handler using the config from the database with
	### the given +appid+ and run it.
	def self::run( appid )
		self.log.info "Running application %p" % [ appid ]
		send_spec, recv_spec = self.connection_info_for( appid )
		self.log.info "  config specs: %s <-> %s" % [ send_spec, recv_spec ]
		new( appid, send_spec, recv_spec ).run
	end


	### Return the send_spec and recv_spec for the given +appid+ from the current configuration
	### database. Returns +nil+ if no Handler is configured with +appid+ as its +sender_id+.
	def self::connection_info_for( appid )
		self.log.debug "Looking up handler spec for appid %p" % [ appid ]
		hconfig = Mongrel2::Config::Handler.by_send_ident( appid ).first or
			raise ArgumentError, "no handler with a send_ident of %p configured" % [ appid ]

		self.log.debug "  found: %s" % [ hconfig.values ]
		return hconfig.send_spec, hconfig.recv_spec
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new instance of the handler with the specified +app_id+, +send_spec+,
	### and +recv_spec+.
	def initialize( app_id, send_spec, recv_spec ) # :notnew:
		@app_id = app_id
		@conn   = Mongrel2::Connection.new( app_id, send_spec, recv_spec )
	end


	######
	public
	######

	# The handler's Mongrel2::Connection object.
	attr_reader :conn

	# The app ID the app was created with
	attr_reader :app_id


	### Run the handler.
	def run
		self.log.info "Starting up %p" % [ self ]
		self.set_signal_handlers
		self.start_accepting_requests

		return self # For chaining
	ensure
		self.restore_signal_handlers
		self.log.info "Done: %p" % [ self ]
	end


	### Return the Mongrel2::Config::Handler that corresponds to this app's
	### appid.
	def handler_config
		return Mongrel2::Config::Handler.by_send_ident( self.app_id ).first
	end


	### Shut down the handler.
	def shutdown
		self.log.info "Shutting down."
		@conn.close
	end


	### Restart the handler. You should override this if you want to re-establish
	### database connections, flush caches, or other restart-ey stuff.
	def restart
		self.log.info "Restarting"
		old_conn = @conn
		@conn = @conn.dup
		self.log.debug "  conn %p -> %p" % [ old_conn, @conn ]
		old_conn.close
	end


	### Start a loop, accepting a request and handling it.
	def start_accepting_requests
		until @conn.closed?
			req = @conn.receive
			self.log.info( req.inspect )
			res = self.dispatch_request( req )

			if res
				self.log.info( res.inspect )
				@conn.reply( res ) unless @conn.closed?
			end
		end
	rescue ZMQ::Error => err
		unless @conn.closed?
			self.log.error "%p while accepting requests: %s" % [ err.class, err.message ]
			self.log.debug { err.backtrace.join("\n  ") }

			retry
		end
	end


	### Invoke a handler method appropriate for the given +request+.
	def dispatch_request( request )
		if request.is_disconnect?
			self.log.debug "disconnect!"
			self.handle_disconnect( request )
			return nil

		elsif request.upload_started?
			self.log.debug "async upload start!"
			return self.handle_async_upload_start( request )

		else
			self.log.debug "%s request." % [ request.headers['METHOD'] ]
			case request
			when Mongrel2::WebSocket::ClientHandshake
				return self.handle_websocket_handshake( request )
			when Mongrel2::WebSocket::Frame
				return self.handle_websocket( request )
			when Mongrel2::HTTPRequest
				return self.handle( request )
			when Mongrel2::JSONRequest
				return self.handle_json( request )
			when Mongrel2::XMLRequest
				return self.handle_xml( request )
			else
				self.log.error "Unhandled request type %s (%p)" %
					[ request.headers['METHOD'], request.class ]
				return nil
			end
		end
	end


	### Returns a string containing a human-readable representation of the Handler suitable
	### for debugging.
	def inspect
		return "#<%p:0x%016x conn: %p>" % [
			self.class,
			self.object_id * 2,
			self.conn,
		]
	end


	#
	# :section: Handler Methods
	# These methods are the principle mechanism for defining the functionality of
	# your handler. The logic that dispatches to these methods is all contained in
	# the #dispatch_request method, so if you want to do something completely different,
	# you should override that instead.
	#

	### The main handler function: handle the specified HTTP +request+ (a Mongrel2::Request) and
	### return a response (Mongrel2::Response). If not overridden, this method returns a
	### '204 No Content' response.
	def handle( request )
		self.log.warn "No default handler; responding with '204 No Content'"
		response = request.response
		response.status = HTTP::NO_CONTENT

		return response
	end


	### Handle a JSON message +request+. If not overridden, JSON message ('@route')
	### requests are ignored.
	def handle_json( request )
		self.log.warn "Unhandled JSON message request (%p)" % [ request.headers.path ]
		return nil
	end


	### Handle an XML message +request+. If not overridden, XML message ('<route')
	### requests are ignored.
	def handle_xml( request )
		self.log.warn "Unhandled XML message request (%p)" % [ request.headers.pack ]
		return nil
	end


	### Handle a WebSocket frame in +request+. If not overridden, WebSocket connections are
	### closed with a policy error status.
	def handle_websocket( request )
		self.log.warn "Unhandled WEBSOCKET frame (%p)" % [ request.headers.path ]
		res = request.response
		res.make_close_frame( WebSocket::CLOSE_POLICY_VIOLATION )
		self.conn.reply( res)

		self.conn.reply_close( request )

		return nil
	end


	### Handle a WebSocket handshake HTTP +request+. If not overridden, this method drops
	### the connection.
	def handle_websocket_handshake( handshake )
		self.log.warn "Unhandled WEBSOCKET_HANDSHAKE request (%p)" % [ request.headers.path ]
		self.conn.reply_close( request )

		return nil
	end


	### Handle a disconnect notice from Mongrel2 via the given +request+. Its return value
	### is ignored.
	def handle_disconnect( request )
		self.log.info "Unhandled disconnect notice."
		return nil
	end


	### Handle an asynchronous upload start notification. These are sent to notify the
	### handler that a request that exceeds the server's <tt>limits.content_length</tt>
	### has been received. The default implementation cancels any such uploads by
	### replying with an empty string. If the request should be accepted, your handler
	### should override this and do nothing if the request should continue. You'll receive
	### a new request via the regular callback when the upload completes whose entity body
	### is open to the spooled file.
	def handle_async_upload_start( request )
		explanation = "If you wish to handle requests like this, either set your server's "
		explanation << "'limits.content_length' setting to a higher value than %d, or override " %
			 [ request.content_length ]
		explanation << "#handle_async_upload_start."

		self.log.warn "Async upload from %s dropped." % [ request.remote_ip ]
		self.log.info( explanation )

		self.conn.reply_close( request )

		return nil
	end


	#
	# :section: Signal Handling
	# These methods set up some behavior for starting, restarting, and stopping
	# your application when a signal is received. If you don't want signals to
	# be handled, override #set_signal_handlers with an empty method.
	#

	### Set up signal handlers for SIGINT, SIGTERM, SIGINT, and SIGUSR1 that will call the
	### #on_hangup_signal, #on_termination_signal, #on_interrupt_signal, and
	### #on_user1_signal methods, respectively.
	def set_signal_handlers
		Signal.trap( :HUP,  &self.method(:on_hangup_signal) )
		Signal.trap( :TERM, &self.method(:on_termination_signal) )
		Signal.trap( :INT,  &self.method(:on_interrupt_signal) )
		Signal.trap( :USR1, &self.method(:on_user1_signal) )
	end


	### Restore the default signal handlers
	def restore_signal_handlers
		Signal.trap( :HUP,  :DEFAULT )
		Signal.trap( :TERM, :DEFAULT )
		Signal.trap( :INT,  :DEFAULT )
		Signal.trap( :USR1, :DEFAULT )
	end


	### Handle a HUP signal. The default is to restart the handler.
	def on_hangup_signal( signo )
		self.log.warn "Hangup: reconnecting."
		self.restart
	end


	### Handle a TERM signal. Shuts the handler down after handling any current request/s. Also
	### aliased to #on_interrupt_signal.
	def on_termination_signal( signo )
		self.log.warn "Halting on signal #{signo} (Thread: %p vs. main: %p)" %
			[ Thread.current, Thread.main ]
		self.shutdown
	end
	alias_method :on_interrupt_signal, :on_termination_signal


	### Handle a USR1 signal. Writes a message to the log by default.
	def on_user1_signal( signo )
		self.log.info "Checkpoint: User signal."
	end

end # class Mongrel2::Handler

