#!/usr/bin/env ruby

require 'uri'
require 'pathname'

require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/config' unless defined?( Mongrel2::Config )
require 'mongrel2/constants'


# Mongrel2 Server configuration class
class Mongrel2::Config::Server < Mongrel2::Config( :server )
	include Mongrel2::Constants

	### As of Mongrel2/1.7.5:
	# CREATE TABLE server (id INTEGER PRIMARY KEY,
	#     uuid TEXT,
	#     access_log TEXT,
	#     error_log TEXT,
	#     chroot TEXT DEFAULT '/var/www',
	#     pid_file TEXT,
	#     default_host TEXT,
	#     name TEXT DEFAULT '',
	#     bind_addr TEXT DEFAULT "0.0.0.0",
	#     port INTEGER,
	#     use_ssl INTEGER default 0);

	#
	# :section: Associations
	#

	##
	# The hosts[rdoc-ref:Mongrel2::Config::Host] that belong to this server.
	one_to_many :hosts

	##
	# The filters[rdoc-ref:Mongrel2::Config::Filter] that will be loaded by this server.
	one_to_many :filters


	#
	# :section: Dataset Methods
	#

	##
	# Return the dataset for looking up a server by its UUID.
	# :singleton-method: by_uuid
	# :call-seq:
	#    by_uuid( uuid )
	def_dataset_method( :by_uuid ) {|uuid| filter(:uuid => uuid).limit(1) }


	#
	# :section: Socket/Pathname Convenience Methods
	#

	### Return a Pathname for the server's chroot directory.
	def chroot_path
		return Pathname( self.chroot )
	end


	### Return the URI for its control socket.
	def control_socket_uri
		# Find the control socket relative to the server's chroot
		csock_uri = Mongrel2::Config.settings[:control_port] || DEFAULT_CONTROL_SOCKET
		self.log.debug "Chrooted control socket uri is: %p" % [ csock_uri ]

		scheme, sock_path = csock_uri.split( '://', 2 )
		self.log.debug "  chrooted socket path is: %p" % [ sock_path ]

		csock_path = self.chroot_path + sock_path
		self.log.debug "  fully-qualified path is: %p" % [ csock_path ]
		csock_uri = "%s://%s" % [ scheme, csock_path ]

		self.log.debug "  control socket URI is: %p" % [ csock_uri ]
		return csock_uri
	end


	### Return the Mongrel2::Control object for the server's control socket.
	def control_socket
		return Mongrel2::Control.new( self.control_socket_uri )
	end


	### Return a Pathname for the server's PID file with its chroot directory prepended.
	def pid_file_path
		pidfile = self.pid_file
		pidfile.slice!( 0, 1 ) if pidfile.start_with?( '/' )

		return self.chroot_path + pidfile
	end


	#
	# :section: Validation Callbacks
	#

	### Sequel validation callback: add errors if the record is invalid.
	def validate
		self.validates_presence [ :access_log, :error_log, :pid_file, :default_host, :port ],
			message: 'is missing or nil'
	end


	### DSL methods for the Server context besides those automatically-generated from its
	### columns.
	module DSLMethods

		### Add a Mongrel2::Config::Host to the Server object with the given +hostname+. If a
		### +block+ is specified, it can be used to further configure the Host.
		def host( name, &block )
			self.target.save( :validate => false )

			self.log.debug "Host [%s] (block: %p)" % [ name, block ]
			adapter = Mongrel2::Config::DSL::Adapter.new( Mongrel2::Config::Host, name: name )
			adapter.target.matching = name
			adapter.instance_eval( &block ) if block
			self.target.add_host( adapter.target )
		end


		### Add a Mongrel2::Config::Filter to the Server object with the specified
		### +path+ (name) and +settings+ hash.
		def filter( path, settings={} )
			self.target.save( :validate => false )

			self.log.debug "Filter [%s]: %p" % [ path, settings ]
			self.target.add_filter( name: path, settings: settings )
		end

	end # module DSLMethods

end # class Mongrel2::Config::Server

