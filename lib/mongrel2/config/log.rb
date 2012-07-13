#!/usr/bin/env ruby

require 'etc'
require 'socket'

require 'mongrel2' unless defined?( Mongrel2 )
require 'mongrel2/config' unless defined?( Mongrel2::Config )

# Mongrel2 configuration Log class
class Mongrel2::Config::Log < Mongrel2::Config( :log )

	### As of Mongrel2/1.7.5:
	# CREATE TABLE log(id INTEGER PRIMARY KEY,
	#     who TEXT,
	#     what TEXT,
	#     location TEXT,
	#     happened_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	#     how TEXT,
	#     why TEXT);

	### Log an entry to the commit log with the given +what+, +why+, +where+, and +how+ values
	### and return it after it's saved.
	def self::log_action( what, why=nil, where=nil, how=nil )
		where ||= Socket.gethostname
		how ||= File.basename( $0 )

		who = Etc.getlogin

		return self.create(
			who:      who,
			what:     what,
			location: where,
			how:      how,
			why:      why
		)
	end


	# :todo: Correct the happened_at, which is set in UTC, but fetched in localtime.

	##
	# :method: id
	# Get the ID of the log entry

	##
	# :method: who
	# Get "who" was reponsible for the event.

	##
	# :method: what
	# Get a description of "what" happened

	##
	# :method: location
	# Get the "where" of the event.

	##
	# :method: happened_at
	# Get the timestamp of the event.

	##
	# :method: how
	# Get a description of "how" the event happened.

	##
	# :method: why
	# Get a description of "why" the event happened.



	### Stringify the log entry and return it.
	def to_s
		# 2011-09-09 19:35:40 [who] @where how: what (why)
		msg = "%{happened_at} [%{who}] @%{location} %{how}: %{what}" % self.values
		msg += " (#{self.why})" if self.why
		return msg
	end

end # class Mongrel2::Config::Log


