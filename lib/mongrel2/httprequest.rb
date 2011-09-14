#!/usr/bin/ruby

require 'mongrel2/request' unless defined?( Mongrel2::Request )
require 'mongrel2/mixins'
require 'mongrel2/httpresponse'


# The Mongrel2 HTTP Request class. Instances of this class represent an HTTP request from
# a Mongrel2 server.
class Mongrel2::HTTPRequest < Mongrel2::Request
	include Mongrel2::Loggable

	# HTTP verbs from RFC2616
	HANDLED_HTTP_METHODS = [ :OPTIONS, :GET, :HEAD, :POST, :PUT, :DELETE, :TRACE, :CONNECT ]

	register_request_type( self, *HANDLED_HTTP_METHODS )


	### Override the type of response returned by this request type.
	def self::response_class
		return Mongrel2::HTTPResponse
	end


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

end # class Mongrel2::HTTPRequest

# vim: set nosta noet ts=4 sw=4:
