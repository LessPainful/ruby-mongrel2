#!/usr/bin/ruby

require 'yajl'
require 'yaml'
require 'pathname'
require 'uri'
require 'tnetstring'
require 'loggability'

require 'sequel'

begin
	require 'configurability'
rescue LoadError
	# No-op: it's optional
end

begin
	require 'amalgalite'
	# Rude hack to stop Sequel::Model from complaining if it's subclassed before
	# the first database connection is established. Ugh.
	Sequel::Model.db = Sequel.connect( 'amalgalite:/' ) if Sequel::DATABASES.empty?
rescue LoadError
	require 'sqlite3'
	Sequel::Model.db = Sequel.connect( 'sqlite:/' ) if Sequel::DATABASES.empty?
end


require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/table'
require 'mongrel2/constants'

module Mongrel2

	# The base Mongrel2 database-backed configuration class. It's a subclass of Sequel::Model, so
	# you'll first need to be familiar with Sequel (http://sequel.rubyforge.org/) and
	# especially its Sequel::Model ORM.
	#
	# You will also probably want to refer to the Sequel::Plugins documentation for the
	# validation_helpers[http://sequel.rubyforge.org/rdoc-plugins/classes/Sequel/Plugins/ValidationHelpers.html]
	# and
	# subclasses[http://sequel.rubyforge.org/rdoc-plugins/classes/Sequel/Plugins/Subclasses.html]
	# plugins.
	#
	# == References
	# * http://mongrel2.org/static/book-finalch4.html#x6-260003.4
	#
	class Config < Sequel::Model
		extend Loggability
		include Mongrel2::Constants

		# Loggability API -- set up logging under the 'mongrel2' log host
		log_to :mongrel2

		# Sequel API -- load some plugins
		plugin :validation_helpers
		plugin :subclasses
		plugin :json_serializer
		plugin :serialization


		# Configuration defaults
		CONFIG_DEFAULTS = {
			:configdb => Mongrel2::DEFAULT_CONFIG_URI,
		}
		DEFAULTS = CONFIG_DEFAULTS

		# The Pathname of the SQL file used to create the config database
		CONFIG_SQL    = DATA_DIR + 'config.sql'

		# The Pathname of the SQL file used to add default mimetypes mappings to the config 
		# database
		MIMETYPES_SQL = DATA_DIR + 'mimetypes.sql'


		# Register this class as configurable if Configurability is loaded.
		if defined?( Configurability )
			extend Configurability
			config_key :mongrel2
		end


		# Register custom serializer/deserializer type
		Sequel::Plugins::Serialization.register_format( :tnetstring,
			TNetstring.method( :dump ),
			lambda {|raw| TNetstring.parse( raw ).first} )


		### Return the name of the Sequel SQLite adapter to use. If the amalgalite library
		### is available, this will return 'amalgalite', else it returns 'sqlite'.
		def self::sqlite_adapter
			if defined?( ::Amalgalite )
				return 'amalgalite'
			else
				return 'sqlite'
			end
		end


		### Return a Sequel::Database for an in-memory database via the available SQLite library
		def self::in_memory_db
			return Sequel.connect( adapter: self.sqlite_adapter )
		end


		### Configurability API -- called when the configuration is loaded with the
		### 'mongrel2' section of the config file if there is one. This method can also be used
		### without Configurability by passing an object that can be merged with
		### Mongrel2::Config::CONFIG_DEFAULTS.
		def self::configure( config=nil )
			return unless config

			config = CONFIG_DEFAULTS.merge( config )

			if dbspec = config[ :configdb ]
				# Assume it's a path to a sqlite database if it doesn't have a schema
				dbspec = "%s://%s" % [ self.sqlite_adapter, dbspec ] unless
					dbspec.include?( ':' )
				self.db = Sequel.connect( dbspec )
			end
		end


		### Reset the database connection that all model objects will use to +newdb+, which should
		### be a Sequel::Database.
		def self::db=( newdb )
			self.without_sql_logging( newdb ) do
				super
			end

			if self == Mongrel2::Config
				self.log.debug "Resetting database connection for %d config classes to: %p" %
					[ self.descendents.length, newdb ]
				newdb.logger = Loggability[ Mongrel2 ].proxy_for( newdb )
				newdb.sql_log_level = :debug

				self.descendents.each {|subclass| subclass.db = newdb }
			end
		end


		### Return the Array of currently-configured servers in the config database as
		### Mongrel2::Config::Server objects.
		def self::servers
			return Mongrel2::Config::Server.all
		end


		### Return a Hash of current settings from the config database. The keys are converted to
		### Symbols.
		def self::settings
			setting_hash = Mongrel2::Config::Setting.to_hash( :key, :value )
			return Mongrel2::Table.new( setting_hash )
		end


		### Return the contents of the configuration schema SQL file.
		def self::load_config_schema
			return CONFIG_SQL.read
		end


		### Return the contents of the mimetypes SQL file.
		def self::load_mimetypes_sql
			return MIMETYPES_SQL.read
		end


		### Returns +true+ if the config database has been installed. This currently only
		### checks to see if the 'server' table exists for the sake of speed.
		def self::database_initialized?
			return self.without_sql_logging do
				self.db.table_exists?( :server )
			end
		end


		### Initialize the currently-configured database (if it hasn't been already)
		def self::init_database
			return if self.database_initialized?
			return self.init_database!
		end


		### Initialize the currently-configured database, dropping any existing tables.
		def self::init_database!
			sql = self.load_config_schema
			mimetypes_sql = self.load_mimetypes_sql

			self.log.warn "Installing config schema."

			self.db.execute_ddl( sql )
			self.db.run( mimetypes_sql )

			# Force the associations to reset
			self.db = db
			self.log_action( "Initialized the config database." )
		end


		### Return the name of the current config database, or nil if the current
		### database is an in-memory one.
		def self::dbname
			if self.db.opts[:database]
				return self.db.opts[:database]
			elsif self.db.uri
				return URI( self.db.uri )
			else
				return nil
			end
		end


		### Log an entry to the commit log with the given +what+, +why+, +where+, and +how+ values
		### and return it after it's saved.
		def self::log_action( what, why=nil, where=nil, how=nil )
			Mongrel2::Config::Log.log_action( what, why, where, how )
		end



		#########
		protected
		#########

		### Execute a block after removing all loggers from the current database handle, then
		### restore them before returning.
		def self::without_sql_logging( logged_db=nil )
			logged_db ||= self.db

			loggers_to_restore = logged_db.loggers.dup
			logged_db.loggers.clear
			yield
		ensure
			logged_db.loggers.replace( loggers_to_restore )
		end


	end # class Config


	### Factory method that creates subclasses of Mongrel2::Config.
	def self::Config( source )
		unless Sequel::Model::ANONYMOUS_MODEL_CLASSES.key?( source )
			anonclass = nil
			if source.is_a?( Sequel::Database )
				anonclass = Class.new( Mongrel2::Config )
				anonclass.db = source
			else
				anonclass = Class.new( Mongrel2::Config ).set_dataset( source )
			end

			Sequel::Model::ANONYMOUS_MODEL_CLASSES[ source ] = anonclass
		end

		return Sequel::Model::ANONYMOUS_MODEL_CLASSES[ source ]
	end

	require 'mongrel2/config/directory'
	require 'mongrel2/config/filter'
	require 'mongrel2/config/handler'
	require 'mongrel2/config/host'
	require 'mongrel2/config/proxy'
	require 'mongrel2/config/route'
	require 'mongrel2/config/server'
	require 'mongrel2/config/setting'
	require 'mongrel2/config/mimetype'
	require 'mongrel2/config/log'
	require 'mongrel2/config/statistic'

	require 'mongrel2/config/dsl'

end # module Mongrel2

