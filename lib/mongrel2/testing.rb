#!/usr/bin/env ruby

require 'uri'
require 'pathname'
require 'loggability'
require 'mongrel2'
require 'mongrel2/request'


# A collection of constants and functions for testing Mongrel2 applications,
# as well as Mongrel2 itself.

module Mongrel2

	# A collection of helper functions that are generally useful
	# for testing Mongrel2::Handlers.
	module SpecHelpers
	end # module SpecHelpers


	# A factory for generating Mongrel2::Request objects for testing.
	#
	# Usage:
	#
	#   require 'mongrel2/testing'
	#
	#   describe "MyHandler" do
	#       before( :all ) do
	#           @factory = Mongrel2::RequestFactory.
	#               new( sender_id: 'my-handler',
	#                    route: '/api/v1',
	#                    headers: {accept: 'application/json'} )
	#       end
	#
	#       before( :each ) do
	#           @app = MyHandler.new( 'my-handler', 'tcp://0.0.0.0:5556',
	#                                 'tcp://0.0.0.0:5555' )
	#       end
	#
	#       it "handles a JSON request for GET /" do
	#           request = @factory.get( '/api/v1' )
	#           response = @app.dispatch_request( request )
	#           #...
	#       end
	#   end
	#
	class RequestFactory
		extend Loggability

		# Loggability API -- set up logging under the 'mongrel2' log host
		log_to :mongrel2

		# Default testing UUID (sender_id)
		DEFAULT_TEST_UUID = 'BD17D85C-4730-4BF2-999D-9D2B2E0FCCF9'

		# Default connection ID
		DEFAULT_CONN_ID = 0

		# 0mq socket specifications for Handlers
		TEST_SEND_SPEC = 'tcp://127.0.0.1:9998'
		TEST_RECV_SPEC = 'tcp://127.0.0.1:9997'

		# The testing URL to use by default
		DEFAULT_TESTING_URL   = URI( 'http://localhost:8080/a_handler' )

		DEFAULT_TESTING_HOST  = DEFAULT_TESTING_URL.host
		DEFAULT_TESTING_PORT  = DEFAULT_TESTING_URL.port
		DEFAULT_TESTING_ROUTE = DEFAULT_TESTING_URL.path

		# The default set of headers used for HTTP requests
		DEFAULT_TESTING_HEADERS  = {
			"x-forwarded-for" => "127.0.0.1",
			"accept-language" => "en-US,en;q=0.8",
			"accept-encoding" => "gzip,deflate,sdch",
			"connection"      => "keep-alive",
			"accept-charset"  => "UTF-8,*;q=0.5",
			"accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
			"user-agent"      => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_1) " +
			                     "AppleWebKit/535.1 (KHTML, like Gecko) Chrome/13.0.782.112 " +
			                     "Safari/535.1",
			"VERSION"         => "HTTP/1.1",
		}

		# The defaults used by the HTTP request factory
		DEFAULT_FACTORY_CONFIG = {
			:sender_id => DEFAULT_TEST_UUID,
			:conn_id   => DEFAULT_CONN_ID,
			:host      => DEFAULT_TESTING_HOST,
			:port      => DEFAULT_TESTING_PORT,
			:route     => DEFAULT_TESTING_ROUTE,
			:headers   => DEFAULT_TESTING_HEADERS,
		}

		# Freeze all testing constants
		constants.each do |cname|
			const_get(cname).freeze
		end


		### Return the default testing headers hash for the receiving class.
		def self::default_headers
			return const_get( :DEFAULT_TESTING_HEADERS )
		end


		### Return the default configuration for the receiving factory class.
		def self::default_factory_config
			return const_get( :DEFAULT_FACTORY_CONFIG )
		end


		#############################################################
		###	I N S T A N C E   M E T H O D S
		#############################################################

		### Create a new RequestFactory with the given +config+, which will be merged with
		### DEFAULT_FACTORY_CONFIG.
		def initialize( config={} )
			config[:headers] = self.class.default_headers.merge( config[:headers] ) if config[:headers]
			config = self.class.default_factory_config.merge( config )

			@sender_id = config[:sender_id]
			@host      = config[:host]
			@port      = config[:port]
			@route     = config[:route]
			@headers   = Mongrel2::Table.new( config[:headers] )

			@conn_id = 0
		end

		######
		public
		######

		attr_accessor :sender_id, :host, :port, :route, :conn_id
		attr_reader :headers

		#
		# :section: HTTP verb methods
		#

		### Create a new OPTIONS Mongrel2::Request with the specified +uri+ and +headers+.
		def options( uri, headers={} )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = self.make_merged_headers( :OPTIONS, uri, headers )
			rclass = Mongrel2::Request.subclass_for_method( :OPTIONS )

			return rclass.new( self.sender_id, self.conn_id.to_s, uri.to_s, headers )
		end


		### Create a new GET Mongrel2::Request for the specified +uri+ and +headers+.
		def get( uri, headers={} )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = self.make_merged_headers( :GET, uri, headers )
			rclass = Mongrel2::Request.subclass_for_method( :GET )

			return rclass.new( self.sender_id, self.conn_id.to_s, uri.to_s, headers )
		end


		### Create a new HEAD Mongrel2::Request for the specified +uri+ and +headers+.
		def head( uri, headers={} )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = self.make_merged_headers( :HEAD, uri, headers )
			rclass = Mongrel2::Request.subclass_for_method( :HEAD )

			return rclass.new( self.sender_id, self.conn_id.to_s, uri.to_s, headers )
		end


		### Create a new POST Mongrel2::Request for the specified +uri+ with
		### the given +body+ and +headers+.
		def post( uri, body='', headers={} )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = self.make_merged_headers( :POST, uri, headers )
			rclass = Mongrel2::Request.subclass_for_method( :POST )

			req = rclass.new( self.sender_id, self.conn_id.to_s, uri.to_s, headers, body )

			return req
		end


		### Create a new PUT Mongrel2::Request for the specified +uri+ with
		### the given +body+ and +headers+.
		def put( uri, body='', headers={} )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = self.make_merged_headers( :PUT, uri, headers )
			rclass = Mongrel2::Request.subclass_for_method( :PUT )

			req = rclass.new( self.sender_id, self.conn_id.to_s, uri.to_s, headers, body )

			return req
		end


		### Create a new DELETE Mongrel2::Request for the specified +uri+ with
		### the given +headers+.
		def delete( uri, headers={} )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = self.make_merged_headers( :DELETE, uri, headers )
			rclass = Mongrel2::Request.subclass_for_method( :DELETE )

			return rclass.new( self.sender_id, self.conn_id.to_s, uri.to_s, headers )
		end


		#########
		protected
		#########

		### Merge the factory's headers with +userheaders+, and then merge in the
		### special headers that Mongrel2 adds that are based on the +uri+ and other
		### server attributes.
		def make_merged_headers( verb, uri, userheaders )
			headers = self.headers.merge( userheaders )
			uri = URI( uri )

			# Add mongrel headers
			headers.uri       = uri.to_s
			headers.path      = uri.path
			headers['METHOD'] = verb.to_s
			headers.host      = "%s:%d" % [ self.host, self.port ]
			headers.query     = uri.query if uri.query
			headers.pattern   = self.route

			return headers
		end

	end # RequestFactory


	# A factory for generating WebSocket request objects for testing.
	#
	class WebSocketFrameFactory < Mongrel2::RequestFactory
		include Mongrel2::Constants

		# The default host
		DEFAULT_TESTING_HOST  = 'localhost'
		DEFAULT_TESTING_PORT  = '8113'
		DEFAULT_TESTING_ROUTE = '/ws'

		# The default WebSocket opcode
		DEFAULT_OPCODE = :text

		# Default headers
		DEFAULT_TESTING_HEADERS = {
			'METHOD'                => 'WEBSOCKET',
			'PATTERN'               => '/ws',
			'URI'                   => '/ws',
			'VERSION'               => 'HTTP/1.1',
			'PATH'                  => '/ws',
			'upgrade'               => 'websocket',
			'host'                  => DEFAULT_TESTING_HOST,
			'sec-websocket-key'     => 'rBP9u8uxVvIYrH/8bNOPwQ==',
			'sec-websocket-version' => '13',
			'connection'            => 'Upgrade',
			'origin'                => "http://#{DEFAULT_TESTING_HOST}",
			'FLAGS'                 => '0x89', # FIN + PING
			'x-forwarded-for'       => '127.0.0.1'
		}

		# The defaults used by the websocket request factory
		DEFAULT_FACTORY_CONFIG = {
			:sender_id     => DEFAULT_TEST_UUID,
			:conn_id       => DEFAULT_CONN_ID,
			:host          => DEFAULT_TESTING_HOST,
			:port          => DEFAULT_TESTING_PORT,
			:route         => DEFAULT_TESTING_ROUTE,
			:headers       => DEFAULT_TESTING_HEADERS,
		}

		DEFAULT_HANDSHAKE_BODY = 'GR7M5bFPiY2GvVc5a7CIMErQ18Q='

		# Freeze all testing constants
		constants.each do |cname|
			const_get(cname).freeze
		end


		### Create a new factory using the specified +config+.
		def initialize( config={} )
			config[:headers] = DEFAULT_TESTING_HEADERS.merge( config[:headers] ) if config[:headers]
			config = DEFAULT_FACTORY_CONFIG.merge( config )

			@sender_id = config[:sender_id]
			@host      = config[:host]
			@port      = config[:port]
			@route     = config[:route]
			@headers   = Mongrel2::Table.new( config[:headers] )

			@conn_id   = 0
		end

		######
		public
		######

		### Create an initial websocket handshake request and return it.
		def handshake( uri, *subprotocols )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = if subprotocols.last.is_a?( Hash ) then subprotocols.pop else {} end
			headers = self.make_merged_headers( uri, 0, headers )
			headers.delete( :flags )

			unless subprotocols.empty?
				protos = subprotocols.map( &:to_s ).join( ', ' )
				headers.sec_websocket_protocol = protos
			end

			rclass = Mongrel2::Request.subclass_for_method( :WEBSOCKET_HANDSHAKE )

			return rclass.new( self.sender_id, self.conn_id.to_s, self.route, headers, DEFAULT_HANDSHAKE_BODY.dup )
		end


		### Create a new request with the specified +uri+, +data+, and +flags+.
		def create( uri, data, *flags )
			raise "Request doesn't route through %p" % [ self.route ] unless
				uri.start_with?( self.route )

			headers = if flags.last.is_a?( Hash ) then flags.pop else {} end
			flagheader = make_flags_header( flags )
			headers = self.make_merged_headers( uri, flagheader, headers )
			rclass = Mongrel2::Request.subclass_for_method( :WEBSOCKET )

			return rclass.new( self.sender_id, self.conn_id.to_s, self.route, headers, data )
		end


		### Create a continuation frame.
		def continuation( uri, payload='', *flags )
			flags << :continuation
			return self.create( uri, payload, flags )
		end


		### Create a text frame.
		def text( uri, payload='', *flags )
			flags << :text
			return self.create( uri, payload, flags )
		end


		### Create a binary frame.
		def binary( uri, payload='', *flags )
			flags << :binary
			return self.create( uri, payload, flags )
		end


		### Create a close frame.
		def close( uri, payload='', *flags )
			flags << :close << :fin
			return self.create( uri, payload, flags )
		end


		### Create a ping frame.
		def ping( uri, payload='', *flags )
			flags << :ping << :fin
			return self.create( uri, payload, flags )
		end


		### Create a pong frame.
		def pong( uri, payload='', *flags )
			flags << :pong << :fin
			return self.create( uri, payload, flags )
		end



		#########
		protected
		#########

		### Merge the factory's headers with +userheaders+, and then merge in the
		### special headers that Mongrel2 adds that are based on the +uri+ and other
		### server attributes.
		def make_merged_headers( uri, flags, userheaders )
			headers = self.headers.merge( userheaders )
			uri = URI( uri )

			# Add mongrel headers
			headers.uri       = uri.to_s
			headers.path      = uri.path
			headers.host      = "%s:%d" % [ self.host, self.port ]
			headers.query     = uri.query if uri.query
			headers.pattern   = self.route
			headers.origin    = "http://#{headers.host}"
			headers.flags     = "0x%02x" % [ flags ]

			return headers
		end


		#######
		private
		#######

		### Make a flags value out of flag Symbols that correspond to the flag
		### bits and opcodes: [ :fin, :rsv1, :rsv2, :rsv3, :continuation,
		### :text, :binary, :close, :ping, :pong ]. If the flags contain
		### Integers instead, they are ORed with the result.
		def make_flags_header( *flag_symbols )
			flag_symbols.flatten!
			flag_symbols.compact!

			self.log.debug "Making a flags header for symbols: %p" % [ flag_symbols ]

			return flag_symbols.inject( 0x00 ) do |flags, flag|
				case flag
				when :fin
					flags | WebSocket::FIN_FLAG
				when :rsv1
					flags | WebSocket::RSV1_FLAG
				when :rsv2
					flags | WebSocket::RSV2_FLAG
				when :rsv3
					flags | WebSocket::RSV3_FLAG
				when :continuation, :text, :binary, :close, :ping, :pong
					# Opcodes clear any other opcodes present
					flags ^= ( flags & WebSocket::OPCODE_BITMASK )
					flags | WebSocket::OPCODE[ flag ]
				when Integer
					flags | flag
				else
					raise ArgumentError, "Don't know what the %p flag is." % [ flag ]
				end
			end
		end

	end # class WebSocketFrameFactory

end # module Mongrel2

