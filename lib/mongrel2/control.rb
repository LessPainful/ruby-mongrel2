#!/usr/bin/ruby

require 'zmq'
require 'yajl'
require 'pathname'
require 'tnetstring'
require 'loggability'

require 'mongrel2' unless defined?( Mongrel2 )


# An interface to the Mongrel2 control port.
#
# == References
# (http://mongrel2.org/static/book-finalch4.html#x6-390003.8)
class Mongrel2::Control
	extend Loggability

	# Loggability API -- set up logging under the 'mongrel2' log host
	log_to :mongrel2


	# The default zmq connection spec to use when talking to a mongrel2 server
	DEFAULT_PORT = 'ipc://run/control'


	### Create a new control port object using the current configuration.
	def initialize( port=DEFAULT_PORT )
		check_port( port )
		@ctx = Mongrel2.zmq_context
		@socket = @ctx.socket( ZMQ::REQ )
		@socket.setsockopt( ZMQ::LINGER, 0 )
		@socket.connect( port.to_s )
	end


	######
	public
	######

	# The control port ZMQ::REQ socket
	attr_reader :socket


	### Stops the server using a SIGINT. Returns a hash with a ':msg' key
	### that describes what happened on success.
	def stop
		self.request( :stop )
	end


	### Reloads the server using a SIGHUP. Returns a hash with a ':msg' key
	### that describes what happened on success.
	def reload
		self.request( :reload )
	end
	alias_method :restart, :reload


	### Terminates the server with SIGTERM. Returns a hash with a ':msg' key
	### that describes what happened on success.
	def terminate
		self.request( :terminate )
	end


	### Return an Array of Hashes, one for each command the server supports.
	###
	### Example:
	###   [
	###     {:name=>"stop", :help=>"stop the server (SIGINT)"},
	###     {:name=>"reload", :help=>"reload the server"},
	###     {:name=>"help", :help=>"this command"},
	###     {:name=>"control_stop", :help=>"stop control port"},
	###     {:name=>"kill", :help=>"kill a connection"},
	###     {:name=>"status", :help=>"status, what=['net'|'tasks']"},
	###     {:name=>"terminate", :help=>"terminate the server (SIGTERM)"},
	###     {:name=>"time", :help=>"the server's time"},
	###     {:name=>"uuid", :help=>"the server's uuid"},
	###     {:name=>"info", :help=>"information about this server"}
	###   ]
	def help
		self.request( :help )
	end


	### Returns the server’s UUID as a String.
	###
	### Example:
	###   [{:uuid=>"28F6DCCF-28EB-48A4-A5B0-ED71D224FAE0"}]
	def uuid
		self.request( :uuid )
	end


	### Return information about the server.
	###
	### Example:
	###   [{:port=>7337,
	###     :bind_addr=>"0.0.0.0",
	###     :uuid=>"28F6DCCF-28EB-48A4-A5B0-ED71D224FAE0",
	###     :chroot=>"/var/www",
	###     :access_log=>"/var/www/logs/admin-access.log",
	###     :error_log=>"/logs/admin-error.log",
	###     :pid_file=>"./run/admin.pid",
	###     :default_hostname=>"localhost"}]
	def info
		self.request( :info )
	end


	### Returns an Array of Hashes, one for each currently running task.
	###
	### Example:
	###   [
	###     {:id=>1, :system=>false, :name=>"SERVER", :state=>"read fd", :status=>"idle"},
	###     {:id=>2, :system=>false, :name=>"Handler_task", :state=>"read handler", :status=>"idle"},
	###     {:id=>3, :system=>false, :name=>"control", :state=>"read handler", :status=>"running"},
	###     {:id=>4, :system=>false, :name=>"ticker", :state=>"", :status=>"idle"},
	###     {:id=>5, :system=>true, :name=>"fdtask", :state=>"yield", :status=>"ready"}
	###   ]
	def tasklist
		self.request( :status, :what => 'tasks' )
	end


	### Returns an Array of Hashes, one for each connection to the server.
	###
	### Example:
	###   [
	###     {:id=>9, :fd=>27, :type=>1, :last_ping=>0, :last_read=>0, :last_write=>0, 
	###      :bytes_read=>319, :bytes_written=>1065}
	###   ]
	def conn_status
		self.request( :status, :what => 'net' )
	end


	### Returns the server's time as a Time object.
	def time
		response = self.request( :time )
		return nil if response.empty?
		return Time.at( response.first[:time].to_i )
	end


	### Does a forced close on the socket that is at the specified +conn_id+.
	def kill( conn_id )
		self.request( :kill, :id => conn_id )
	end


	### Shuts down the control port permanently in case you want to keep it from 
	### being accessed for some reason.
	def control_stop
		self.request( :control_stop )
	end


	### Close the control port connection.
	def close
		self.socket.close
	end


	#########
	protected
	#########

	### Send a raw request to the server, asking it to perform the +command+ with the specified
	### +options+ hash and return the results.
	def request( command, options={} )
		msg = TNetstring.dump([ command, options ])
		self.log.debug "Request: %p" % [ msg ]
		self.socket.send( msg )

		response = self.socket.recv
		self.log.debug "Response: %p" % [ response ]
		return unpack_response( response )
	end


	#######
	private
	#######

	### Unpack a Mongrel2 Control Port response (TNetString encoded table) as an
	### Array of Hashes.
	def unpack_response( response )
		table = TNetstring.parse( response ).first
		self.log.debug "Unpacking response: %p" % [ table ]

		# Success
		if table.key?( 'headers' )
			headers, rows = table.values_at( 'headers', 'rows' )
			headers.map!( &:to_sym )

			return rows.collect do |row|
				Hash[ [headers, row].transpose ]
			end

		# Error
		elsif table.key?( 'code' )
			# {"code"=>"INVALID_ARGUMENT", "error"=>"Invalid argument type."}
			raise Mongrel2::ControlError.new( table['code'], table['error'] )

		else
			raise ScriptError, "Don't know how to handle response: %p" % [ table ]
		end
	end


	### Check the path of the specified port if it's an 'ipc' URL, ensuring that a pipe exists
	### there, and raising an exception if none does.
	def check_port( port )
		scheme, path = port.split( '://' )
		return unless scheme == 'ipc'

		raise "%s: not a socket" % [ path ] unless FileTest.socket?( path )

		return true
	end

end # class Mongrel2::Control

# vim: set nosta noet ts=4 sw=4:

