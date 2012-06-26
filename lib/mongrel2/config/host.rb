#!/usr/bin/env ruby

require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/config' unless defined?( Mongrel2::Config )

# Mongrel2 Host configuration class
class Mongrel2::Config::Host < Mongrel2::Config( :host )

	### As of Mongrel2/1.7.5:
	# CREATE TABLE host (id INTEGER PRIMARY KEY, 
	#     server_id INTEGER,
	#     maintenance BOOLEAN DEFAULT 0,
	#     name TEXT,
	#     matching TEXT);


	#
	# :section: Associations
	#

	##
	# The routes[rdoc-ref:Mongrel2::Config::Route] that this host has.
	one_to_many :routes

	##
	# The server[rdoc-ref:Mongrel2::Config::Server] this host belongs to.
	many_to_one :server


	#
	# :section: Hooks
	#

	### Clean up the host's routes when it's destroyed.
	def before_destroy
		self.routes.each( &:destroy )
	end


	#
	# :section: DSL mixin
	#

	### DSL methods for the Server context besides those automatically-generated from its
	### columns.
	module DSLMethods

		### Add a Mongrel2::Config::Route to the Host object.
		def route( path, target, opts={} )
			self.target.save
			self.log.debug "Route %s -> %p [%p]" % [ path, target, opts ]

			args = { :path => path, :target => target }
			args.merge!( opts )
			route = Mongrel2::Config::Route.new( args )

			self.target.add_route( route )
		end


		# These are route _arguments_, so they need to be declared in Host's scope rather
		# than Route's.

		### Create a new Mongrel2::Config::Directory object for the specified +base+ and
		### return it.
		def directory( base, index_file='index.html', default_ctype='text/plain', opts={} )
			opts.merge!( :base => base, :index_file => index_file, :default_ctype => default_ctype )
			return Mongrel2::Config::Directory.create( opts )
		end


		### Create a new Mongrel2::Config::Proxy object for the specified +addr+ and
		### +port+ and return it.
		def proxy( addr, port=80 )
			return Mongrel2::Config::Proxy.create( :addr => addr, :port => port )
		end


		### Create a new Mongrel2::Config::Handler object with the specified +send_spec+, 
		### +send_ident+, +recv_spec+, +recv_ident+, and +options+ and return it.
		def handler( send_spec, send_ident, recv_spec=nil, recv_ident='', options={} )
			# Shift the opts hash over if the other optional args were omitted
			if recv_spec.is_a?( Hash )
				options = recv_spec
				recv_spec = nil
			elsif recv_ident.is_a?( Hash )
				options = recv_ident
				recv_ident = ''
			end

			# Default to one port below the request spec
			unless recv_spec
				port = send_spec[ /:(\d+)$/, 1 ] or
					"Can't guess default port for a send_spec without one (%p)" % [ send_spec ]
				recv_spec = URI( send_spec )
				recv_spec.port = port.to_i - 1
			end

			options.merge!(
				:send_spec  => send_spec.to_s,
				:send_ident => send_ident,
				:recv_spec  => recv_spec.to_s,
				:recv_ident => recv_ident
			)

			existing = Mongrel2::Config::Handler.filter( :send_ident => send_ident )
			unless existing.select( :id ).empty?
				self.log.debug "Dropping existing %p handler." % [ send_ident ]
				existing.delete
			end

			self.log.debug "Creating handler with options: %p" % [ options ]
			return Mongrel2::Config::Handler.create( options )
		end

	end # module DSLMethods

end # class Mongrel2::Config::Host

