#!/usr/bin/ruby
#encoding: utf-8

require 'time'
require 'loggability'

require 'mongrel2/response' unless defined?( Mongrel2::Response )
require 'mongrel2/constants'


# The Mongrel2 HTTP Response class.
class Mongrel2::HTTPResponse < Mongrel2::Response
	extend Loggability
	include Mongrel2::Constants

	# Loggability API -- set up logging under the 'mongrel2' log host
	log_to :mongrel2

	# The format for building valid HTTP responses
	STATUS_LINE_FORMAT = "HTTP/1.1 %03d %s".freeze

	# A network End-Of-Line
	EOL = "\r\n".freeze

	# The default content type
	DEFAULT_CONTENT_TYPE = 'application/octet-stream'.freeze


	### Set up a few things specific to HTTP responses
	def initialize( sender_id, conn_id, body='', headers={} ) # :notnew:
		if body.is_a?( Hash )
			headers = body
			body = ''
		end

		super( sender_id, conn_id, body )

		@headers = Mongrel2::Table.new
		@status = nil
		self.set_defaults

		@headers.merge!( headers )
	end


	######
	public
	######

	# The response headers (a Mongrel2::Table)
	attr_reader :headers
	alias_method :header, :headers

	# The HTTP status code
	attr_accessor :status


	### Set up response default headers, etc.
	def set_defaults
		@headers[:server] = Mongrel2.version_string( true )
	end


	### Stringify the response
	def to_s
		return [
			self.status_line,
			self.header_data,
			self.bodiless? ? '' : super
		].join( "\r\n" )
	end


	### Send the response status to the client
	def status_line
		self.log.debug "Building status line for status: %p" % [ self.status ]

		st = self.status || (self.body.size.zero? ? HTTP::NO_CONTENT : HTTP::OK)

		return STATUS_LINE_FORMAT % [ st, HTTP::STATUS_NAME[st] ]
	end


	### Returns true if the response is ready to be sent to the client.
	def handled?
		return ! @status.nil?
	end
	alias_method :is_handled?, :handled?


	### Returns true if the response status means the response
	### shouldn't have a body.
	def bodiless?
		return HTTP::BODILESS_HTTP_RESPONSE_CODES.include?( self.status )
	end


	### Return the numeric category of the response's status code (1-5)
	def status_category
		return 0 if self.status.nil?
		return (self.status / 100).ceil
	end


	### Return true if response is in the 1XX range
	def status_is_informational?
		return self.status_category == 1
	end


	### Return true if response is in the 2XX range
	def status_is_successful?
		return self.status_category == 2
	end


	### Return true if response is in the 3XX range
	def status_is_redirect?
		return self.status_category == 3
	end


	### Return true if response is in the 4XX range
	def status_is_clienterror?
		return self.status_category == 4
	end


	### Return true if response is in the 5XX range
	def status_is_servererror?
		return self.status_category == 5
	end


	### Return the current response Content-Type.
	def content_type
		return self.headers[ :content_type ]
	end


	### Set the current response Content-Type.
	def content_type=( type )
		return self.headers[ :content_type ] = type
	end


	### Clear any existing headers and body and restore them to their defaults
	def reset
		@headers.clear
		@body.truncate( 0 )
		@status = nil

		self.set_defaults

		return true
	end


	### Return the current response header as a valid HTTP string after
	### normalizing them.
	def header_data
		return self.normalized_headers.to_s
	end


	### Get a copy of the response headers table with any auto-generated or
	### calulated headers set.
	def normalized_headers
		headers = self.headers.dup

		headers[:date] ||= Time.now.httpdate
		headers[:content_length] ||= self.get_content_length

		if self.bodiless?
			headers.delete( :content_type )
		else
			headers[:content_type] ||= DEFAULT_CONTENT_TYPE.dup
		end

		return headers
	end


	### Get the length of the body IO. If the IO's offset is somewhere other than
	### the beginning or end, the size of the remainder is used.
	def get_content_length
		if self.bodiless?
			return 0
		elsif self.body.pos.nonzero? && !self.body.eof?
			return self.body.size - self.body.pos
		else
			return self.body.size
		end
	end


	### Set the Connection header to allow pipelined HTTP.
	def keepalive=( value )
		self.headers[:connection] = value ? 'keep-alive' : 'close'
	end
	alias_method :pipelining_enabled=, :keepalive=


	### Returns +true+ if the response has pipelining enabled.
	def keepalive?
		ka_header = self.headers[:connection]
		return !ka_header.nil? && ka_header =~ /keep-alive/i
		return false
	end
	alias_method :pipelining_enabled?, :keepalive?


	#########
	protected
	#########

	### Return the details to include in the contents of the #inspected object.
	def inspect_details
		return %Q{%s -- %d headers, %0.2fK body (%p)} % [
			self.status_line,
			self.headers.length,
			(self.get_content_length / 1024.0),
			self.body,
		]
	end

end # class Mongrel2::Response

# vim: set nosta noet ts=4 sw=4:

