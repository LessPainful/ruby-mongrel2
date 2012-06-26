#!/usr/bin/env ruby

require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/config' unless defined?( Mongrel2::Config )

# Mongrel2 Handler configuration class
class Mongrel2::Config::Handler < Mongrel2::Config( :handler )

	### As of Mongrel2/1.7.5:
	# CREATE TABLE handler (id INTEGER PRIMARY KEY,
	#     send_spec TEXT,
	#     send_ident TEXT,
	#     recv_spec TEXT,
	#     recv_ident TEXT,
	#    raw_payload INTEGER DEFAULT 0,
	#    protocol TEXT DEFAULT 'json');


	#
	# :section: Associations
	#

	##
	# The routes[rdoc-ref:Mongrel2::Config::Route] that refer to this Handler
	one_to_many :routes, :key => :target_id, :conditions => { target_type: 'handler' }


	# The list of 0mq transports Mongrel2 can use; "You need to use the
	# ZeroMQ syntax for configuring them, but this means with one
	# configuration format you can use handlers that are using UDP, TCP,
	# Unix, or PGM transports." Note that I'm assuming by 'udp' Zed means
	# 'epgm', as I can't find any udp 0mq transport.
	VALID_SPEC_SCHEMES = %w[epgm tcp ipc pgm]

	# The list of valid protocols
	#--
	# handler.h: typedef enum { HANDLER_PROTO_JSON, HANDLER_PROTO_TNET } handler_protocol_t;
	VALID_PROTOCOLS = %w[json tnetstring]


	##
	# :method: by_send_ident( uuid )
	#
	# Look up a Handler by its send_ident, which should be a +uuid+ or similar String.
	def_dataset_method( :by_send_ident ) do |ident|
		filter( :send_ident => ident )
	end


	### Validate the object prior to saving it.
	def validate
		self.validate_idents
		self.validate_specs
		self.validate_protocol
		self.validate_uniqueness
	end


	#########
	protected
	#########

	### Turn nil recv_ident values into the empty string before validating.
	def before_validation
		self.recv_ident ||= ''
	end


	### Validate the send_ident and recv_ident
	### --
	### :FIXME: I'm not sure if this is actually necessary, but it seems like
	###         the ident should at least be UUID-like like the server ident.
	def validate_idents
		unless self.send_ident =~ /^\w[\w\-]+$/
			errmsg = "[%p]: invalid sender identity (should be UUID-like)" % [ self.send_ident ]
			self.log.error( 'send_ident: ' + errmsg )
			self.errors.add( :send_ident, errmsg )
		end

		unless self.recv_ident == '' || self.send_ident =~ /^\w[\w\-]+$/
			errmsg = "[%p]: invalid receiver identity (should be empty string or UUID-like)" %
				[ self.recv_ident ]
			self.log.error( 'send_ident: ' + errmsg )
			self.errors.add( :send_ident, errmsg )
		end
	end


	### Validate the send_spec and recv_spec.
	def validate_specs
		if err = check_0mq_spec( self.send_spec )
			errmsg = "[%p]: %s" % [ self.send_spec, err ]
			self.log.error( 'send_spec: ' + errmsg )
			self.errors.add( :recv_spec, errmsg )
		end

		if err = check_0mq_spec( self.recv_spec )
			errmsg = "[%p]: %s" % [ self.recv_spec, err ]
			self.log.error( 'recv_spec: ' + errmsg )
			self.errors.add( :recv_spec, errmsg )
		end
	end


	### Validate the handler's protocol.
	def validate_protocol
		return unless self.protocol # nil == default
		unless VALID_PROTOCOLS.include?( self.protocol )
			errmsg = "[%p]: invalid" % [ self.protocol ]
			self.log.error( 'protocol: ' + errmsg )
			self.errors.add( :protocol, errmsg )
		end
	end


	### Ensure that handlers are unique.
	def validate_uniqueness
		self.validates_unique( :send_ident, :send_spec, :recv_spec )
	end


	#######
	private
	#######

	### Returns +true+ if +url+ is a valid 0mq transport specification.
	def check_0mq_spec( url )
		return "must not be nil" unless url

		u = URI( url )
		return "invalid 0mq transport #{u.scheme}" unless VALID_SPEC_SCHEMES.include?( u.scheme )

		return nil
	rescue URI::InvalidURIError
		return 'not a URI; should be something like "tcp://127.0.0.1:9998"'
	end

end # class Mongrel2::Config::Handler

