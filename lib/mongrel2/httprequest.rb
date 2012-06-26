#!/usr/bin/ruby

require 'loggability'

require 'mongrel2/request' unless defined?( Mongrel2::Request )
require 'mongrel2/httpresponse'


# The Mongrel2 HTTP Request class. Instances of this class represent an HTTP request from
# a Mongrel2 server.
class Mongrel2::HTTPRequest < Mongrel2::Request
	extend Loggability

	# Loggability API -- set up logging under the 'mongrel2' log host
	log_to :mongrel2

	# HTTP verbs from RFC2616
	HANDLED_HTTP_METHODS = [ :OPTIONS, :GET, :HEAD, :POST, :PUT, :DELETE, :TRACE, :CONNECT ]

	# Mongrel2::Request API -- register this class as handling the HTTP verbs
	register_request_type( self, *HANDLED_HTTP_METHODS )


	### Override the type of response returned by this request type.
	def self::response_class
		return Mongrel2::HTTPResponse
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Return +true+ if the request is an HTTP/1.1 request and its
	### 'Connection' header indicates that the connection should stay
	### open.
	def keepalive?
		unless self.headers[:version] == 'HTTP/1.1'
			self.log.debug "Not an http/1.1 request: not persistent"
			return false
		end
		conn_header = self.headers[:connection]
		if !conn_header
			self.log.debug "No Connection header: assume persistence"
			return true
		end

		if conn_header.split( /\s*,\s*/ ).include?( 'close' )
			self.log.debug "Connection: close header."
			return false
		else
			self.log.debug "Connection header didn't contain 'close': assume persistence"
			return true
		end
	end


	### Returns the size of the request's entity body, as specified by its
	### 'Content-Length' header. Note that this may or may not correspond to
	### the actual byte size of the body.
	def content_length
		return 0 unless self.header.member?( :content_length )
		return Integer( self.header.content_length )
	end


	### Fetch the mimetype of the request's content, as set in its header.
	def content_type
		return self.headers.content_type
	end


	### Set the current request's Content-Type.
	def content_type=( type )
		return self.headers.content_type = type
	end


	### Fetch the encoding type of the request's content, as set in its header.
	def content_encoding
		return self.headers.content_encoding
	end


	### Set the request's encoding type.
	def content_encoding=( type )
		return self.headers.content_encoding = type
	end


	#########
	protected
	#########

	### Return the details to include in the contents of the #inspected object.
	def inspect_details
		return %Q{[%s] "%s %s %s" -- %0.2fK body} % [
			self.headers.x_forwarded_for,
			self.headers[:method],
			self.headers.uri,
			self.headers.version,
			(self.body.size / 1024.0),
		]
	end

end # class Mongrel2::HTTPRequest

# vim: set nosta noet ts=4 sw=4:

