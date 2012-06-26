#!/usr/bin/env ruby

require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/config' unless defined?( Mongrel2::Config )

# Mongrel2 Route configuration class
class Mongrel2::Config::Route < Mongrel2::Config( :route )

	### As of Mongrel2/1.7.5:
	# CREATE TABLE route (id INTEGER PRIMARY KEY,
	#     path TEXT,
	#     reversed BOOLEAN DEFAULT 0,
	#     host_id INTEGER,
	#     target_id INTEGER,
	#     target_type TEXT);


	### Return the Route that corresponds to the given +request+.
	def self::for_request( request )
		pattern = request.headers.pattern
		return self.filter( path: pattern ).first
	end


	#
	# :section: Associations
	#

	##
	# The Mongrel2::Config::Host this route belongs to.
	many_to_one :host


	### Fetch the route's target, which is either a Mongrel2::Config::Directory, 
	### Mongrel2::Config::Proxy, or Mongrel2::Config::Handler object.
	def target
		case self.target_type
		when 'dir'
			return Mongrel2::Config::Directory[ self.target_id ]
		when 'proxy'
			return Mongrel2::Config::Proxy[ self.target_id ]
		when 'handler'
			return Mongrel2::Config::Handler[ self.target_id ]
		else
			raise ArgumentError, "unknown target type %p" % [ self.target_type ]
		end
	end


	### Set the target of the route to +object+, which should be one of the classes
	### returned from #target.
	def target=( object )
		case object
		when Mongrel2::Config::Directory
			self.target_type = 'dir'
		when Mongrel2::Config::Proxy
			self.target_type = 'proxy'
		when Mongrel2::Config::Handler
			self.target_type = 'handler'
		else
			raise ArgumentError, "unknown target type %p" % [ object.class ]
		end

		self.target_id = object.id
	end

end # class Mongrel2::Config::Route

