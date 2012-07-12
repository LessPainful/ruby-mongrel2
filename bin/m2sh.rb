#!/usr/bin/env ruby

require 'uri'
require 'pathname'
require 'fileutils'
require 'tnetstring'
require 'loggability'

require 'trollop'
require 'highline'

# Have to do it this way to avoid the vendored 'sysexits' under OSX.
gem 'sysexits'
require 'sysexits'

require 'mongrel2'
require 'mongrel2/config'


# A tool for interacting with a Mongrel2 config database and server. This isn't
# quite a replacement for the real m2sh yet; here's what I have working so far:
#
#   [√]    load  Load a config.
#   [√]  config  Alias for load.
#   [-]   shell  Starts an interactive shell.
#   [√]  access  Prints the access log.
#   [√] servers  Lists the servers in a config database.
#   [√]   hosts  Lists the hosts in a server.
#   [√]  routes  Lists the routes in a host.
#   [√]  commit  Adds a message to the log.
#   [√]     log  Prints the commit log.
#   [√]   start  Starts a server.
#   [√]    stop  Stops a server.
#   [√]  reload  Reloads a server.
#   [√] running  Tells you what's running.
#   [-] control  Connects to the control port.
#   [√] version  Prints the Mongrel2 and m2sh version.
#   [√]    help  Get help, lists commands.
#   [-]    uuid  Prints out a randomly generated UUID.
#
# I just use 'uuidgen' to generate uuids (which is all m2sh does, as
# well), so I don't plan to implement that. The 'control' command is more-easily
# accessed via pry+Mongrel2::Control, so I'm not going to implement that, either.
# Everything else should be analagous to (or better than) the m2sh that comes with
# mongrel2. I implemented the 'shell' mode, but I found I never used it, and it
# introduced a dependency on the Termios library, so I removed it.
#
class Mongrel2::M2SHCommand
	extend ::Sysexits,
	       Loggability
	include Sysexits,
	        Mongrel2::Constants

	# Loggability API -- set up logging under the 'strelka' log host
	log_to :mongrel2


	# Make a HighLine color scheme
	COLOR_SCHEME = HighLine::ColorScheme.new do |scheme|
		scheme[:header]    = [ :bold, :yellow ]
		scheme[:subheader] = [ :bold, :white ]
		scheme[:key]       = [ :white ]
		scheme[:value]     = [ :bold, :white ]
		scheme[:error]     = [ :red ]
		scheme[:warning]   = [ :yellow ]
		scheme[:message]   = [ :reset ]
	end


	# Number of items to store in history by default
	DEFAULT_HISTORY_SIZE = 100


	# Class instance variables
	@command_help = Hash.new {|h,k| h[k] = { :desc => nil, :usage => ''} }
	@prompt = @option_parser = nil


	### Add a help string for the given +command+.
	def self::help( command, helpstring=nil )
		if helpstring
			@command_help[ command.to_sym ][:desc] = helpstring
		end

		return @command_help[ command.to_sym ][:desc]
	end


	### Add/fetch the +usagestring+ for +command+.
	def self::usage( command, usagestring=nil )
		if usagestring
			prefix = usagestring[ /\A(\s+)/, 1 ]
			usagestring.gsub!( /^#{prefix}/m, '' ) if prefix

			@command_help[ command.to_sym ][:usage] = usagestring
		end

		return @command_help[ command.to_sym ][:usage]
	end


	### Return the global Highline prompt object, creating it if necessary.
	def self::prompt
		unless @prompt
			@prompt = HighLine.new
			# @prompt.wrap_at = @prompt.output_cols - 3
		end

		return @prompt
	end


	### Run the utility with the given +args+.
	def self::run( args )
		HighLine.color_scheme = COLOR_SCHEME

		oparser = self.make_option_parser
		opts = Trollop.with_standard_exception_handling( oparser ) do
			oparser.parse( args )
		end

		command = oparser.leftovers.shift
		self.new( opts ).run( command, *oparser.leftovers )
		exit :ok

	rescue => err
		self.log.fatal "Oops: %s: %s" % [ err.class.name, err.message ]
		self.log.debug { '  ' + err.backtrace.join("\n  ") }

		exit :software_error
	end


	### Return a String that describes the available commands, e.g., for the 'help'
	### command.
	def self::make_command_table
		commands = self.available_commands

		# Build the command table
		col1len = commands.map( &:length ).max
		return commands.collect do |cmd|
			helptext = self.help( cmd.to_sym ) or next # no help == invisible command
			"%s  %s" % [
				self.prompt.color(cmd.rjust(col1len), :key),
				self.prompt.color(helptext, :value)
			]
		end.compact
	end


	### Return an Array of the available commands.
	def self::available_commands
		return self.public_instance_methods( false ).
			map( &:to_s ).
			grep( /_command$/ ).
			map {|methodname| methodname.sub(/_command$/, '') }.
			sort
	end


	### Create and configure a command-line option parser for the command.
	### Returns a Trollop::Parser.
	def self::make_option_parser
		unless @option_parser
			progname = File.basename( $0 )
			default_configdb = Mongrel2::DEFAULT_CONFIG_URI

			# Make a list of the log level names and the available commands
			loglevels = Loggability::LOG_LEVELS.
				sort_by {|name,lvl| lvl }.
				collect {|name,lvl| name.to_s }.
				join( ', ' )
			command_table = self.make_command_table

			@option_parser = Trollop::Parser.new do
				banner "Mongrel2 (Ruby) Shell has these commands available:"

				text ''
				command_table.each {|line| text(line) }
				text ''

				text 'Global Options'
				opt :config, "Specify the config database to use.",
					:default => DEFAULT_CONFIG_URI
				opt :sudo, "Use 'sudo' to run the mongrel2 server."
				opt :port, "Reset the server port to <i> before starting it.",
					:type => :integer
				text ''

				text 'Other Options:'
				opt :debug, "Turn debugging on. Also sets the --loglevel to 'debug'."
				opt :loglevel, "Set the logging level. Must be one of: #{loglevels}",
					:default => Mongrel2.logger.level.to_s
			end
		end

		return @option_parser
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new instance of the command and set it up with the given
	### +options+.
	def initialize( options )
		Loggability.format_as( :color ) if $stderr.tty?
		@options = options

		if @options.debug
			$DEBUG = true
			$VERBOSE = true
			Loggability.level = Logger::DEBUG
		elsif @options.loglevel
			Loggability.level = @options.loglevel
		end

		Mongrel2::Config.configure( :configdb => @options.config )
	end


	######
	public
	######

	# The Trollop options hash the command will read its configuration from
	attr_reader :options


	# Delegate the instance #prompt method to the class method instead
	define_method( :prompt, &self.method(:prompt) )


	### Run the command with the specified +command+ and +args+.
	def run( command, *args )
		command ||= 'help'
		cmd_method = nil

		begin
			cmd_method = self.method( "#{command}_command" )
		rescue NoMethodError => err
			error "No such command"
			exit :usage
		end

		cmd_method.call( *args )
	end


	#
	# Commands
	#

	### The 'help' command
	def help_command( *args )

		# Subcommand help
		if !args.empty?
			command = args.shift

			if self.class.available_commands.include?( command )
				header( self.class.help(command) )
				desc = "\n" + 'Usage: ' + command + ' ' + self.class.usage(command) + "\n"
				message( desc )
			else
				error "No such command %p" % [ command ]
			end

		# Help by itself show the table of available commands
		else
			command_table = self.class.make_command_table
			header "Available Commands"
			message( *command_table )
		end

	end
	help :help, "Show help for a single COMMAND if given, or list available commands if not"
	usage :help, "[COMMAND]"


	### The 'load' command
	def load_command( *args )
		configfile = args.shift or
			raise "No configfile specified."

		runspace = Module.new do
			extend Mongrel2::Config::DSL, FileUtils::Verbose
		end

		header "Loading config from #{configfile}"
		source = File.read( configfile )

		runspace.module_eval( source, configfile, 1 )
	end
	help :load, "Overwrite the config database with the values from the speciifed CONFIGFILE."
	usage :load, <<-END_USAGE
	CONFIGFILE
	Note: the CONFIGFILE should contain a configuration described using the
	Ruby config DSL, not a Python-ish normal one. m2sh already works perfectly
	fine for loading those.
	END_USAGE


	### The 'config' command
	alias_method :config_command, :load_command
	help :config, "Alias for 'load'."


	### The 'init' command
	def init_command( * )
		if Mongrel2::Config.database_initialized?
			abort "Okay, aborting." unless
				self.prompt.agree( "Are you sure you want to destroy the current config? " )
		end

		header "Initializing #{self.options.config}"
		Mongrel2::Config.init_database!
	end
	help :init, "Initialize a new empty config database."


	### The 'access' command
	def access_command( logfile='logs/access.log', * )
		#      1$             2$       3$       4$        5$        6$            7$        8$  9$
		# ["localhost", "127.0.0.1", 53420, 1315533812, "GET", "/favicon.ico", "HTTP/1.1", 404, 0]
		# -> [1315533812] 127.0.0.1:53420 localhost "GET /favicon.ico HTTP/1.1" 404 0
		IO.foreach( logfile ) do |line|
			row, _ = TNetstring.parse( line )
			message %{[%4$d] %2$s:%3$d %1$s "%5$s %6$s %7$s" %8$03d %9$d} % row
		end
	end
	help :access, "Dump the access log."
	usage :access, "[logfile]\nThe logfile defaults to 'logs/access.log'."


	### The 'servers' command
	def servers_command( * )
		header 'SERVERS:'
		Mongrel2::Config.servers.each do |server|
			message "%s [%s]: %s" % [
				self.prompt.color( server.name, :key ),
				server.default_host,
				server.uuid,
			]
		end
	end
	help :servers, "Lists the servers in a config database."


	### The 'hosts' command
	def hosts_command( *args )
		servername = args.shift

		# Start with all servers, then narrow it down if they specified a server name.
		servers = Mongrel2::Config::Server.dataset
		servers = servers.filter( :name => servername ) if servername

		# Output a section for each server
		servers.each do |server|
			header "HOSTS for server #{server.name}:"
			server.hosts.each do |host|
				line = "%d: %s" % [ host.id, host.name ]
				line << " /%s/" % [ host.matching ] if host.matching != host.name

				message( line )
			end

			$stdout.puts
		end
	end
	help :hosts, "Lists the hosts in a server, or in all servers if none is specified."
	usage :hosts, "[server]"


	### The 'routes' command
	def routes_command( *args )
		servername = args.shift
		hostname = args.shift

		# Start with all hosts, then narrow it down if a server and/or host was given.
		hosts = Mongrel2::Config::Host.dataset
		if servername
			server = Mongrel2::Config::Server[ servername ] or
				raise "No such server '#{servername}'"
			hosts = server.hosts_dataset
		end
		hosts = hosts.filter( :name => hostname ) if hostname

		# Output a section for each host
		hosts.each do |host|
			header "ROUTES for host #{host.server.name}/#{host.name}:"

			host.routes.each do |route|
				message( route.path )
			end
		end

	end
	help :routes, "Show the routes under a host."
	usage :routes, "[server [host]]"


	### The 'commit' command
	def commit_command( *args )
		what, where, why, how = *args
		what ||= ''

		log = Mongrel2::Config::Log.log_action( what, where, why, how )

		header "Okay, logged."
		message( log.to_s )
	end
	help :commit, "Add a message to the commit log."
	usage :commit, "[WHAT [WHERE [WHY [HOW]]]]"


	### The 'log' command
	def log_command( *args )
		header "Log Messages"
		Mongrel2::Config::Log.order_by( :happened_at ).each do |log|
			message( log.to_s )
		end
	end
	help :log, "Prints the commit log."


	### The 'start' command
	def start_command( *args )
		server = find_server( args.shift )
		mongrel2 = ENV['MONGREL2'] || 'mongrel2'

		if options.port
			message "Resetting %s server's port to %d" % [ server.name, options.port ]
			server.port = options.port
			server.save
		end

		cmd = [ mongrel2, Mongrel2::Config.dbname.to_s, server.uuid ]
		cmd.unshift( 'sudo' ) if self.options.sudo

		url = "http%s://%s:%d" % [
			server.use_ssl? ? 's' : '',
			server.bind_addr,
			server.port,
		]
		header "Starting mongrel2 at: #{url}"
		exec( *cmd )
	end
	help :start, "Starts a server."
	usage :start, <<-END_USAGE
	[SERVER]
	If not specified, SERVER is assumed to be the only server entry in the
	current config. If there are more than one, you must specify a SERVER.

	The SERVER can be a uuid, hostname, or server name, and are searched for
	in that order.
	END_USAGE


	### The 'reload' command
	def reload_command( *args )
		server = find_server( args.shift )
		control = server.control_socket

		header "Reloading '%s'" % [ server.name ]
		control.reload
		control.close
		message "done."
	end
	help :reload, "Reload the specified server's configuration"
	usage :reload, "[server]"


	### The 'stop' command
	def stop_command( *args )
		server = find_server( args.shift )
		control = server.control_socket

		header "Stopping '%s' gracefully." % [ server.name ]
		control.stop
		control.close
		message "done."
	end
	help :stop, "Stop the specified server gracefully"
	usage :stop, "[server]"


	### The 'running' command
	def running_command( *args )
		server = find_server( args.shift )
		pidfile = server.pid_file_path

		header "Checking the status of the '%s' server." % [ server.name ]
		unless pidfile.exist?
			message "Not running: PID file (%s) doesn't exist." % [ pidfile ]
			exit :noinput
		end

		pid = Integer( pidfile.read )
		begin
			Process.kill( 0, pid )
		rescue Errno::ESRCH
			message "  mongrel2 at PID %d is NOT running" % [ pid ]
			exit :unavailable
		rescue => err
			error "  %p while signalling PID %d: %s" % [ err.class, pid, err.message ]
		end

		message "  mongrel2 at PID %d is running." % [ pid ]
	end
	help :running, "Show the status of a server."
	usage :running, "[server]"


	### The 'bootstrap' command.
	def bootstrap_command( *args )
		scriptname = args.shift || DEFAULT_CONFIG_SCRIPT
		template   = Mongrel2::DATA_DIR + 'config.rb.in'
		data       = template.read

		data.gsub!( /%% PWD %%/, Dir.pwd )

		header "Writing a config-generation script to %s" % [ scriptname ]
		File.open( scriptname, File::WRONLY|File::EXCL|File::CREAT, 0755, encoding: 'utf-8' ) do |fh|
			fh.print( data )
		end
		message "Done."
	end
	help :bootstrap, "Generate a basic config-generation script."
	usage :boostrap, "[scriptname]"


	### The 'quickstart' command.
	def quickstart_command( *args )
		configfile = 'config.rb'

		header "Quickstart!"
		self.bootstrap_command( configfile )
		edit( configfile )
		self.load_command( configfile )
		self.start_command()
	end
	help :quickstart, "Set up a basic mongrel2 server and run it."
	usage :quickstart


	### The 'version' command
	def version_command( *args )
		message( "<%= color 'Version:', :header %> " + Mongrel2.version_string(true) )
	end
	help :version, "Prints the Ruby-Mongrel2 version."


	#
	# Utility methods
	#

	#######
	private
	#######

	### Output normal output
	def message( *parts )
		self.prompt.say( parts.map(&:to_s).join($/) )
	end


	### Output the given +text+ highlighted as a header.
	def header( text )
		message( self.prompt.color(text, :header) )
	end


	### Output the given +text+ highlighted as an error.
	def error( text )
		message( self.prompt.color(text, :error) )
	end


	### Read command line history from HISTORY_FILE
	def read_history
		histfile = HISTORY_FILE.expand_path

		if histfile.exist?
			lines = histfile.readlines.collect {|line| line.chomp }
			self.log.debug "Read %d saved history commands from %s." % [ lines.length, histfile ]
			Readline::HISTORY.push( *lines )
		else
			self.log.debug "History file '%s' was empty or non-existant." % [ histfile ]
		end
	end


	### Save command line history to HISTORY_FILE
	def save_history
		histfile = HISTORY_FILE.expand_path

		lines = Readline::HISTORY.to_a.reverse.uniq.reverse
		lines = lines[ -DEFAULT_HISTORY_SIZE, DEFAULT_HISTORY_SIZE ] if
			lines.length > DEFAULT_HISTORY_SIZE

		self.log.debug "Saving %d history lines to %s." % [ lines.length, histfile ]

		histfile.open( File::WRONLY|File::CREAT|File::TRUNC ) do |ofh|
			ofh.puts( *lines )
		end
	end


	### Search the current mongrel2 config for a server matching +serverspec+ and
	### return it as a Mongrel2::Config::Server object.
	def find_server( serverspec=nil )
		server = nil
		servers = Mongrel2::Config.servers

		raise "No servers are configured." if servers.empty?

		# If there's only one configured server, just make sure if a serverspec was given
		# that it would have matched.
		if servers.length == 1
			server = servers.first if !serverspec ||
				servers.first.values_at( :uuid, :default_host, :name ).include?( serverspec )

		# Otherwise, require an argument and search for the desired server if there is one
		else
			raise "You must specify a server uuid/hostname/name when more " +
			      "than one server is configured." if servers.length > 1 && !serverspec

			server = servers.find {|s| s.uuid == serverspec } ||
			         servers.find {|s| s.default_host == serverspec } ||
			         servers.find {|s| s.name == serverspec }
		end

		raise "No servers match '#{serverspec}'" unless server

		return server
	end


	### Invoke the user's editor on the given +filename+ and return the exit code
	### from doing so.
	def edit( filename )
		editor = ENV['EDITOR'] || ENV['VISUAL'] || DEFAULT_EDITOR
		system editor, filename.to_s
		unless $?.success? || editor =~ /vim/i
			raise "Editor exited with an error status (%d)" % [ $?.exitstatus ]
		end
	end



end # class Mongrel2::M2SHCommand


Mongrel2::M2SHCommand.run( ARGV.dup )

