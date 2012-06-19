#!/usr/bin/env ruby
# encoding: utf-8

require 'loggability'
require 'pathname'
require 'mongrel2/config'
require 'mongrel2/handler'


# An example of a WebSocket (RFC6455) Mongrel2 application that echoes back whatever
# (non-control) frames you send it. It will also ping all of its clients and disconnect
# ones that don't reply within a given period.
class WebSocketEchoServer < Mongrel2::Handler
	include Mongrel2::WebSocket::Constants

	# Number of seconds to wait between heartbeat PING frames
	HEARTBEAT_RATE = 5.0

	# Number of seconds to wait for a data frame or a PONG before considering
	# a socket idle
	SOCKET_IDLE_TIMEOUT = 15.0


	# Add an instance variable to keep track of connections, and one for the
	# heartbeat thread.
	def initialize( * )
		super
		@connections = {}
		@heartbeat = nil
	end


	######
	public
	######

	# A Hash of last seen times keyed by [sender ID, connection ID] tuple
	attr_reader :connections

	# The Thread that sends PING frames to connected sockets and cull any
	# that don't reply within SOCKET_IDLE_TIMEOUT seconds
	attr_reader :heartbeat


	# Called by Mongrel2::Handler when it starts accepting requests. Overridden
	# to start up the heartbeat thread.
	def start_accepting_requests
		self.start_heartbeat
		super
	end


	# Called by Mongrel2::Handler when the server is restarted. Overridden to
	# restart the heartbeat thread.
	def restart
		self.stop_heartbeat
		super
		self.start_heartbeat
	end


	# Called by Mongrel2::Handler when the server is shut down. Overridden to
	# stop the heartbeat thread.
	def shutdown
		self.stop_heartbeat
		super
	end


	# Mongrel2 will send a disconnect notice when a client's connection closes;
	# delete the connection when it does.
	def handle_disconnect( request )
		self.log.info "Client %d: disconnect." % [ request.conn_id ]
		self.connections.delete( [request.sender_id, request.conn_id] )
		return nil
	end


	# Non-websocket (e.g., plain HTTP) requests would ordinarily just get
	# a 204 NO CONTENT response, but we tell Mongrel2 to just drop such connections
	# immediately.
	def handle( request )
		self.log.info "Regular HTTP request (%s): closing channel." % [ request ]
		self.conn.reply_close( request )
		return nil
	end


	# This is the main handler for WebSocket requests. Each frame comes in as a
	# Mongrel::WebSocket::Frame object, and then is dispatched according to what
	# opcode it has.
	def handle_websocket( frame )

		# Log each frame
		self.log.info "%s/%d: %s%s [%s]: %p" % [
			frame.sender_id,
			frame.conn_id,
			frame.opcode.to_s.upcase,
			frame.fin? ? '' : '(cont)',
			frame.headers.x_forwarded_for,
			frame.payload.read( 20 ),
		]
		frame.payload.rewind

		# If a client sends an invalid frame, close their connection, but politely.
		if !frame.valid?
			self.log.error "  invalid frame from client: %s" % [ frame.errors.join(';') ]
			res = frame.response( :close )
			res.set_status( CLOSE_PROTOCOL_ERROR )
			return res
		end

		# Update the 'last-seen' time unless the connection is closing
		unless frame.opcode == :close
			@connections[ [frame.sender_id, frame.conn_id] ] = Time.now
		end

		# Use the opcode to decide what method to call
		self.log.debug "Handling a %s frame." % [ frame.opcode ]
		handler = self.method( "handle_%s_frame" % [frame.opcode] )
		return handler.call( frame )
	end


	# Handle TEXT, BINARY, and CONTINUATION frames by replying with an echo of the
	# same data. Fragmented frames get echoed back as-is without any reassembly.
	def handle_text_frame( frame )
		self.log.info "Echoing data frame: %p" % [ frame ]

		# Make the response frame
		response = frame.response
		response.fin = frame.fin?
		IO.copy_stream( frame.payload, response.payload )

		return response
	end
	alias_method :handle_binary_frame, :handle_text_frame
	alias_method :handle_continuation_frame, :handle_text_frame


	# Handle close frames
	def handle_close_frame( frame )

		# There will still be a connection slot if this close originated with
		# the client. In that case, reply with the ACK CLOSE frame
		self.conn.reply( frame.response(:close) ) if
			self.connections.delete( [frame.sender_id, frame.conn_id] )

		self.conn.reply_close( frame )
		return nil
	end


	# Handle a PING frame; the response is a PONG with the same payload.
	def handle_ping_frame( frame )
		return frame.response
	end


	# Handle a PONG frame; nothing really to do
	def handle_pong_frame( frame )
		return nil
	end


	# Start a thread that will periodically ping connected sockets and remove any
	# connections that don't reply
	def start_heartbeat
		self.log.info "Starting heartbeat thread."
		@heartbeat = Thread.new do
			Thread.current.abort_on_exception = true
			self.log.debug "  Heartbeat thread started: %p" % [ Thread.current ]

			# Use a thread-local variable to signal the thread to shut down
			Thread.current[ :shutdown ] = false
			until Thread.current[ :shutdown ]

				# If there are active connections, remove any that have
				# timed out and ping the rest
				unless self.connections.empty?
					self.cull_idle_sockets
					self.ping_all_sockets
				end

				self.log.debug "    heartbeat thread sleeping"
				sleep( HEARTBEAT_RATE )
				self.log.debug "    heartbeat thread waking up"
			end

			self.log.info "Hearbeat thread exiting."
		end
	end


	# Tell the heartbeat thread to exit.
	def stop_heartbeat
		@heartbeat[ :shutdown ] = true
		@heartbeat.run.join if @heartbeat.alive?
	end


	# Disconnect any sockets that haven't sent any frames for at least
	# SOCKET_IDLE_TIMEOUT seconds.
	def cull_idle_sockets
		self.log.debug "Culling idle sockets."

		earliest = Time.now - SOCKET_IDLE_TIMEOUT

		self.connections.each do |(sender_id, conn_id), lastframe|
			next unless earliest > lastframe

			# Make a CLOSE frame
			frame = Mongrel2::WebSocket::Frame.new( sender_id, conn_id, '', {}, '' )
			frame.opcode = :close
			frame.set_status( CLOSE_EXCEPTION )

			# Use the connection directly so we can send a frame and close the
			# connection
			self.conn.reply( frame )
			self.conn.send_close( sender_id, conn_id )
		end
	end


	# Send a PING frame to all connected sockets.
	def ping_all_sockets
		self.log.debug "Pinging all connected sockets."

		self.connections.each do |(sender_id, conn_id), hash|
			frame = Mongrel2::WebSocket::Frame.new( sender_id, conn_id, '', {}, 'heartbeat' )
			frame.opcode = :ping
			frame.fin = true

			self.log.debug "  %s/%d: PING" % [ sender_id, conn_id ]
			self.conn.reply( frame )
		end

		self.log.debug "  done with pings."
	end


end # class RequestDumper

Loggability.level = $DEBUG||$VERBOSE ? :debug : :info
Loggability.format_as( :color ) if $stdin.tty?

# Point to the config database, which will cause the handler to use
# its ID to look up its own socket info.
Mongrel2::Config.configure( :configdb => 'examples.sqlite' )
WebSocketEchoServer.run( 'ws-echo' )

