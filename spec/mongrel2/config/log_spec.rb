#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'socket'
require 'rspec'

require 'spec/lib/constants'
require 'spec/lib/helpers'

require 'mongrel2'
require 'mongrel2/config'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::Config::Log do

	before( :all ) do
		setup_logging( :fatal )
		setup_config_db()
	end

	after( :all ) do
		reset_logging()
	end


	it "has a convenience method for writing to the commit log" do
		what  = 'load etc/mongrel2.conf'
		why   = 'updating'
		where = 'localhost'
		how   = 'm2sh'

		log = Mongrel2::Config::Log.log_action( what, why, where, how )

		log.what.should == what
		log.why.should == why
		log.location.should == where
		log.how.should == how
	end

	it "has reasonable defaults for 'where' and 'how'" do
		what  = 'load etc/mongrel2.conf'
		why   = 'updating'

		log = Mongrel2::Config::Log.log_action( what, why )

		log.location.should == Socket.gethostname
		log.how.should == File.basename( $0 )
	end

	describe "an entry" do

		before( :each ) do
			@log = Mongrel2::Config::Log.new(
				who:         'who',
				what:        'what',
				location:    'location',
				happened_at: Time.at( 1315598592 ),
				how:         'how'
			)
		end


		it "stringifies as a readable log file line" do

			# 2011-09-09 20:29:47 -0700 [mgranger] @localhost m2sh: load etc/mongrel2.conf (updating)
			@log.to_s.should =~ %r{
				^
				(?-x:\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [\+\-]\d{4} )
				\[who\] \s
				@location \s
				how: \s
				what
				$
			}x
		end

		it "stringifies with a reason if it has one" do
			@log.why = 'Because'

			# 2011-09-09 20:29:47 -0700 [mgranger] @localhost m2sh: load etc/mongrel2.conf (updating)
			@log.to_s.should =~ %r{
				^
				(?-x:\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [\+\-]\d{4} )
				\[who\] \s
				@location \s
				how: \s
				what \s
				\(Because\)
				$
			}x
		end

	end

end

