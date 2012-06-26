#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'

require 'spec/lib/helpers'

require 'mongrel2'
require 'mongrel2/config'
require 'mongrel2/handler'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::Handler do

	# Make a handler class for testing that only ever handles one request, and
	# keeps track of any requests it handles and their responses.
	class OneShotHandler < Mongrel2::Handler
		def initialize( * )
			@transactions = {}
			super
		end

		attr_reader :transactions

		# Overridden to accept one request and shut down
		def dispatch_request( request )
			response = super
			self.transactions[ request ] = response
			self.shutdown
			return response
		end

	end # class OneShotHandler


	before( :all ) do
		setup_logging( :fatal )
		setup_config_db()
	end

	after( :all ) do
		reset_logging()
	end


	# Ensure 0MQ never actually gets called
	before( :each ) do
		@ctx = double( "0mq context" )
		@request_sock = double( "request socket", :setsockopt => nil, :connect => nil, :close => nil )
		@response_sock = double( "response socket", :setsockopt => nil, :connect => nil, :close => nil )

		@ctx.stub( :socket ).with( ZMQ::PULL ).and_return( @request_sock )
		@ctx.stub( :socket ).with( ZMQ::PUB ).and_return( @response_sock )

		Mongrel2.instance_variable_set( :@zmq_ctx, @ctx )
	end

	after( :each ) do
		Mongrel2.instance_variable_set( :@zmq_ctx, nil )
	end



	context "with a Handler entry in the config database" do

		before( :each ) do
			@handler_config = {
				:send_spec  => TEST_SEND_SPEC,
				:send_ident => TEST_UUID,
				:recv_spec  => TEST_RECV_SPEC,
			}

			Mongrel2::Config::Handler.dataset.truncate
			Mongrel2::Config::Handler.create( @handler_config )
		end

		it "can look up connection information given an application ID" do
			Mongrel2::Handler.connection_info_for( TEST_UUID ).
				should == [ TEST_SEND_SPEC, TEST_RECV_SPEC ]
		end

		it "has a convenience method for instantiating and running a Handler given an " +
		   "application ID" do

			req = make_request()
			@request_sock.should_receive( :recv ).and_return( req )

			res = OneShotHandler.run( TEST_UUID )

			# It should have pulled its connection info from the Handler entry in the database
			res.conn.app_id.should == TEST_UUID
			res.conn.sub_addr.should == TEST_SEND_SPEC
			res.conn.pub_addr.should == TEST_RECV_SPEC
		end

		it "knows what handler config corresponds to its" do
			req = make_request()
			@request_sock.should_receive( :recv ).and_return( req )

			res = OneShotHandler.run( TEST_UUID )

			res.handler_config.should be_a( Mongrel2::Config::Handler )
			res.handler_config.send_spec.should == TEST_SEND_SPEC
			res.handler_config.recv_spec.should == TEST_RECV_SPEC
		end

	end


	context "without a Handler entry for it in the config database" do

		before( :each ) do
			Mongrel2::Config::Handler.dataset.truncate
		end

		it "raises an exception if no handler with its appid exists in the config DB" do
			Mongrel2::Config::Handler.dataset.truncate
			expect {
				Mongrel2::Handler.connection_info_for( TEST_UUID )
			}.should raise_error()
		end

	end


	it "dispatches HTTP requests to the #handle method" do
		req = make_request()
		@request_sock.should_receive( :recv ).and_return( req )

		res = OneShotHandler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::HTTPRequest )
		response.should be_a( Mongrel2::HTTPResponse )
		response.status.should == 204
	end

	it "ignores JSON messages by default" do
		req = make_json_request()
		@request_sock.should_receive( :recv ).and_return( req )

		res = OneShotHandler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::JSONRequest )
		response.should be_nil()
	end

	it "dispatches JSON message to the #handle_json method" do
		json_handler = Class.new( OneShotHandler ) do
			def handle_json( request )
				return request.response
			end
		end

		req = make_json_request()
		@request_sock.should_receive( :recv ).and_return( req )

		res = json_handler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::JSONRequest )
		response.should be_a( Mongrel2::Response )
	end

	it "ignores XML messages by default" do
		req = make_xml_request()
		@request_sock.should_receive( :recv ).and_return( req )

		res = OneShotHandler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::XMLRequest )
		response.should be_nil()
	end

	it "dispatches XML message to the #handle_xml method" do
		xml_handler = Class.new( OneShotHandler ) do
			def handle_xml( request )
				return request.response
			end
		end

		req = make_xml_request()
		@request_sock.should_receive( :recv ).and_return( req )

		res = xml_handler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::XMLRequest )
		response.should be_a( Mongrel2::Response )
	end

	it "continues when a ZMQ::Error is received but the connection remains open" do
		req = make_request()

		@request_sock.should_receive( :recv ).and_raise( ZMQ::Error.new("Interrupted system call.") )
		@request_sock.should_receive( :recv ).and_return( req )

		res = OneShotHandler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::HTTPRequest )
		response.should be_a( Mongrel2::HTTPResponse )
		response.status.should == 204
	end

	it "ignores disconnect notices by default" do
		req = make_json_request( :path => '@*', :body => {'type' => 'disconnect'} )
		@request_sock.should_receive( :recv ).and_return( req )

		res = OneShotHandler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::JSONRequest )
		response.should be_nil()
	end

	it "dispatches disconnect notices to the #handle_disconnect method" do
		disconnect_handler = Class.new( OneShotHandler ) do
			def handle_disconnect( request )
				self.log.debug "Doing stuff for disconnected connection %d" % [ request.conn_id ]
			end
		end

		req = make_json_request( :path => '@*', :body => {'type' => 'disconnect'} )
		@request_sock.should_receive( :recv ).and_return( req )

		res = disconnect_handler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		request.should be_a( Mongrel2::JSONRequest )
		response.should be_nil()
	end

	it "cancels async upload notices by default" do
		req = make_request( 'METHOD' => 'POST', :headers => {'x-mongrel2-upload-start' => 'uploadfile.XXX'} )
		@request_sock.should_receive( :recv ).and_return( req )

		res = OneShotHandler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC ).run

		res.transactions.should have( 1 ).member
		request, response = res.transactions.first
		response.should == ''
	end

	it "re-establishes its connection when told to restart" do
		res = OneShotHandler.new( TEST_UUID, TEST_SEND_SPEC, TEST_RECV_SPEC )
		original_conn = res.conn
		res.restart
		res.conn.should_not equal( original_conn )
	end

end

