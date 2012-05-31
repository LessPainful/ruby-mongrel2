#!/usr/bin/env ruby

require 'loggability'
require 'zmq'

#
# A Mongrel2 connector and configuration library for Ruby.
#
# == Author/s
#
# * Michael Granger <ged@FaerieMUD.org>
#
module Mongrel2
	extend Loggability

	# Loggability API -- set up Mongrel2 as a log host
	log_as :mongrel2


	abort "\n\n>>> Mongrel2 requires Ruby 1.9.2 or later. <<<\n\n" if RUBY_VERSION < '1.9.2'

	# Library version constant
	VERSION = '0.24.0'

	# Version-control revision constant
	REVISION = %q$Revision$


	require 'mongrel2/constants'
	include Mongrel2::Constants


	### Get the library version. If +include_buildnum+ is true, the version string will
	### include the VCS rev ID.
	def self::version_string( include_buildnum=false )
		vstring = "Ruby-Mongrel2 %s" % [ VERSION ]
		vstring << " (build %s)" % [ REVISION[/: ([[:xdigit:]]+)/, 1] || '0' ] if include_buildnum
		return vstring
	end


	# ZMQ::Context (lazy-loaded)
	@zmq_ctx = nil

	### Fetch the ZMQ::Context for sockets, creating it if necessary.
	def self::zmq_context
		if @zmq_ctx.nil?
			self.log.info "Using 0MQ %d.%d.%d" % ZMQ.version
			@zmq_ctx = ZMQ::Context.new
		end

		return @zmq_ctx
	end


	require 'mongrel2/exceptions'
	require 'mongrel2/connection'
	require 'mongrel2/handler'
	require 'mongrel2/request'
	require 'mongrel2/httprequest'
	require 'mongrel2/jsonrequest'
	require 'mongrel2/xmlrequest'
	require 'mongrel2/websocket'
	require 'mongrel2/response'
	require 'mongrel2/control'

end # module Mongrel2


# Workaround for rbzmq <= 2.3.0
unless defined?( ZMQ::Error )
	module ZMQ
		Error = ::RuntimeError
	end
end


