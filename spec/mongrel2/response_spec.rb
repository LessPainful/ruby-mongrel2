#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'
require 'tnetstring'

require 'spec/lib/helpers'

require 'mongrel2'
require 'mongrel2/request'
require 'mongrel2/response'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::Response do

	before( :all ) do
		setup_logging( :fatal )
	end

	after( :all ) do
		reset_logging()
	end


	it "can create a matching response given a Mongrel2::Request" do
		req = Mongrel2::Request.new( TEST_UUID, 8, '/path', {}, '' )
		response = Mongrel2::Response.from_request( req )

		response.should be_a( Mongrel2::Response )
		response.sender_id.should == req.sender_id
		response.conn_id.should == req.conn_id
		response.request.should equal( req )
	end


	it "can be created with a body" do
		response = Mongrel2::Response.new( TEST_UUID, 8, 'the body' )
		response.body.read.should == 'the body'
	end

	it "stringifies to its body contents" do
		response = Mongrel2::Response.new( TEST_UUID, 8, 'the body' )
		response.to_s.should == 'the body'
	end

	it "can be streamed in chunks" do
		response = Mongrel2::Response.new( TEST_UUID, 8, 'the body' )
		expect {|b| response.each_chunk(&b) }.to yield_with_args( 'the body' )
	end

	it "wraps stringifiable bodies set via the #body= accessor in a StringIO" do
		response = Mongrel2::Response.new( TEST_UUID, 8 )
		response.body = 'a stringioed body'
		response.body.should be_a( StringIO )
		response.body.string.should == 'a stringioed body'
	end

	it "doesn't try to wrap non-stringfiable bodies in a StringIO" do
		response = Mongrel2::Response.new( TEST_UUID, 8 )
		testbody = Object.new
		response.body = testbody
		response.body.should be( testbody )
	end

	context	"an instance with default values" do

		before( :each ) do
			@response = Mongrel2::Response.new( TEST_UUID, 8 )
		end

		it "has an empty-IO body" do
			@response.body.rewind
			@response.body.read.should == ''
		end

		it "supports the append operator to append objects to the body IO" do
			@response << 'some body stuff' << ' and some more body stuff'
			@response.body.rewind
			@response.body.read.should == 'some body stuff and some more body stuff'
		end

		it "supports #puts for appending objects to the body IO separated by EOL" do
			@response.puts( "some body stuff\n", " and some more body stuff\n\n", :and_a_symbol )
			@response.body.rewind
			@response.body.read.should == "some body stuff\n and some more body stuff\n\nand_a_symbol\n"
		end

	end

end

