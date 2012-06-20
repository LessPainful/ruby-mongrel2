#!/usr/bin/ruby

require 'stringio'
require 'tnetstring'
require 'yajl'
require 'loggability'

require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/table'


# The Mongrel2 Request base class. Derivatives of this class represent a request from
# a Mongrel2 server.
class Mongrel2::Request
	extend Loggability

	# Loggability API -- set up logging under the 'mongrel2' log host
	log_to :mongrel2

	# METHOD header -> request class mapping
	@request_types = Hash.new {|h,k| h[k] = Mongrel2::Request }
	class << self; attr_reader :request_types; end


	### Parse the given +raw_request+ from a Mongrel2 server and return an appropriate
	### request object.
	def self::parse( raw_request )
		sender, conn_id, path, rest = raw_request.split( ' ', 4 )
		self.log.debug "Parsing request for %p from %s:%s (rest: %p)" %
			[ path, sender, conn_id, rest ]

		# Extract the headers and the body, ignore the rest
		headers, rest = TNetstring.parse( rest )
		body, _       = TNetstring.parse( rest )

		# Headers will be a JSON String when not using the TNetString protocol
		if headers.is_a?( String )
			self.log.debug "  parsing old-style headers"
			headers = Yajl::Parser.parse( headers )
		end

		# This isn't supposed to happen, but guard against it anyway
		headers['METHOD'] =~ /^(\w+)$/ or
			raise Mongrel2::UnhandledMethodError, headers['METHOD']
		req_method = $1.untaint.to_sym
		self.log.debug "Request method is: %p" % [ req_method ]
		concrete_class = self.subclass_for_method( req_method )

		return concrete_class.new( sender, conn_id, path, headers, body, raw_request )
	end



	### Register the specified +subclass+ as the class to instantiate when the +METHOD+
	### header is one of the specified +req_methods+. This method exists for frameworks
	### which wish to provide their own Request types.
	###
	### For example, if your framework has a JSONRequest class that inherits from
	### Mongrel2::JSONRequest, and you want it to be returned from Mongrel2::Request.parse
	### for METHOD=JSON requests:
	###
	###   class MyFramework::JSONRequest < Mongrel2::JSONRequest
	###       register_request_type self, 'JSON'
	###
	###       # Override #initialize to do any stuff specific to your
	###       # request type, but you'll likely want to super() to
	###       # Mongrel2::JSONRequest.
	###       def initialize( * )
	###           super
	###           # Do some other stuff
	###       end
	###
	###   end # class MyFramework::JSONRequest
	###
	### If you wish one of your subclasses to be used instead of Mongrel2::Request
	### for the default request class, register it with a METHOD of :__default.
	def self::register_request_type( subclass, *req_methods )
		self.log.debug "Registering %p for %p requests" % [ subclass, req_methods ]
		req_methods.each do |methname|
			if methname == :__default
				# Clear cached lookups
				self.log.info "Registering %p as the default request type." % [ subclass ]
				Mongrel2::Request.request_types.delete_if {|_, klass| klass == Mongrel2::Request }
				Mongrel2::Request.request_types.default_proc = lambda {|h,k| h[k] = subclass }
			else
				self.log.info "Registering %p for the %p method." % [ subclass, methname ]
				Mongrel2::Request.request_types[ methname.to_sym ] = subclass
			end
		end
	end


	### Return the Mongrel2::Request class registered for the request method +methname+.
	def self::subclass_for_method( methname )
		return Mongrel2::Request.request_types[ methname.to_sym ]
	end


	### Return the Mongrel2::Response class that corresponds with the receiver.
	def self::response_class
		return Mongrel2::Response
	end



	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new Request object with the given +sender_id+, +conn_id+, +path+, +headers+,
	### and +body+. The optional +nil+ is for the raw request content, which can be useful
	### later for debugging.
	def initialize( sender_id, conn_id, path, headers, body='', raw=nil )

		@sender_id = sender_id
		@conn_id   = Integer( conn_id )
		@path      = path
		@headers   = Mongrel2::Table.new( headers )
		@raw       = raw

		if self.valid_upload?
			spoolfile = self.uploaded_file
			self.log.info "Using async spool file %s as request entity body." % [ spoolfile ]
			@body = spoolfile.open( 'r' )
		elsif !body.respond_to?( :read )
			self.log.info "Wrapping non-IO (%p) body in a StringIO" % [ body.class ]
			@body = StringIO.new( body, 'r+b' )
		end

		@response  = nil
	end


	######
	public
	######

	# The UUID of the requesting mongrel server
	attr_reader :sender_id

	# The listener ID on the server
	attr_reader :conn_id

	# The path component of the requested URL in HTTP, or the equivalent
	# for other request types
	attr_reader :path

	# The Mongrel2::Table object that contains the request headers
	attr_reader :headers
	alias_method :header, :headers

	# The request body data, if there is any, as an IO object
	attr_reader :body

	# The raw request content, if the request was parsed from mongrel2
	attr_reader :raw


	### Create a Mongrel2::Response that will respond to the same server/connection as
	### the receiver. If you wish your specialized Request class to have a corresponding
	### response type, you can override the Mongrel2::Request.response_class method 
	### to achieve that.
	def response
		return @response ||= self.class.response_class.from_request( self )
	end


	### Return +true+ if the request is a special 'disconnect' notification from Mongrel2.
	def is_disconnect?
		return false
	end


	#
	# :section: Async Upload Support
	# See http://mongrel2.org/static/book-finalch6.html#x8-810005.5 for details.
	#

	### The Pathname, relative to Mongrel2's chroot path, of the uploaded entity body.
	def uploaded_file
		raise Mongrel2::UploadError, "invalid upload: upload headers don't match" unless
			self.upload_headers_match?

		server = Mongrel2::Config::Server.by_uuid( self.sender_id ).first or
			raise Mongrel2::UploadError, "couldn't find the server %p in the config DB" %
			[ self.sender_id ]

		relpath = Pathname( self.headers.x_mongrel2_upload_done )
		chrooted = Pathname( server.chroot ) + relpath

		if chrooted.exist?
			return chrooted
		elsif relpath.exist?
			return relpath
		else
			self.log.error "uploaded body %s not found: tried relative to cwd and server chroot (%s)" %
				[ relpath, server.chroot ]
			raise Mongrel2::UploadError,
				"couldn't find the path to uploaded body."
		end
	end


	### Returns +true+ if this request is an 'asynchronous upload started' notification.
	def upload_started?
		return self.headers.member?( :x_mongrel2_upload_start ) &&
		       !self.headers.member?( :x_mongrel2_upload_done )
	end


	### Returns +true+ if this request is an 'asynchronous upload done' notification.
	def upload_done?
		return self.headers.member?( :x_mongrel2_upload_start ) &&
		       self.headers.member?( :x_mongrel2_upload_done )
	end


	### Returns +true+ if this request is an 'asynchronous upload done' notification
	### and the two headers match (trivial guard against forgery)
	def upload_headers_match?
		return self.upload_done? &&
		       self.headers.x_mongrel2_upload_start == self.headers.x_mongrel2_upload_done
	end


	### Returns true if this request is an asynchronous upload, and the filename of the
	### finished request matches the one from the starting notification.
	def valid_upload?
		return self.upload_done? && self.upload_headers_match?
	end


	#
	# :section: Introspection Methods
	#

	### Returns a string containing a human-readable representation of the Request,
	### suitable for debugging.
	def inspect
		return "#<%p:0x%016x %s (%s/%d)>" % [
			self.class,
			self.object_id * 2,
			self.inspect_details,
			self.sender_id,
			self.conn_id
		]
	end


	#########
	protected
	#########

	### Return the details to include in the contents of the #inspected object. This
	### method allows other request types to provide their own details while keeping
	### the form somewhat consistent.
	def inspect_details
		return "%s -- %d headers, %p body" % [
			self.path,
			self.headers.length,
			self.body.class,
		]
	end

end # class Mongrel2::Request

# vim: set nosta noet ts=4 sw=4:

