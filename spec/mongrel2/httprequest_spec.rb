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
require 'mongrel2/httprequest'
require 'mongrel2/httpresponse'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::HTTPRequest do

	before( :all ) do
		setup_logging( :fatal )
		@factory = Mongrel2::RequestFactory.new( route: '/glamour' )
	end

	before( :each ) do
		@req = @factory.get( '/glamour/test' )
	end

	after( :all ) do
		reset_logging()
	end


	it "can create an HTTPResponse for itself" do
		result = @req.response
		result.should be_a( Mongrel2::HTTPResponse )
		result.sender_id.should == @req.sender_id
		result.conn_id.should == @req.conn_id
	end

	it "remembers its corresponding HTTPResponse if it's created it already" do
		result = @req.response
		result.should be_a( Mongrel2::HTTPResponse )
		result.sender_id.should == @req.sender_id
		result.conn_id.should == @req.conn_id
	end

	it "knows that its connection isn't persistent if it's an HTTP/1.0 request" do
		@req.headers.version = 'HTTP/1.0'
		@req.should_not be_keepalive()
	end

	it "knows that its connection isn't persistent if has a 'close' token in its Connection header" do
		@req.headers.version = 'HTTP/1.1'
		@req.headers[ :connection ] = 'violent, close'
		@req.should_not be_keepalive()
	end

	it "knows that its connection could be persistent if doesn't have a Connection header, " +
	   "and it's an HTTP/1.1 request" do
		@req.headers.version = 'HTTP/1.1'
		@req.headers.delete( :connection )
		@req.should be_keepalive()
	end

	it "knows that its connection is persistent if has a Connection header without a 'close' " +
	   "token and it's an HTTP/1.1 request" do
		@req.headers.version = 'HTTP/1.1'
		@req.headers.connection = 'keep-alive'
		@req.should be_keepalive()
	end

	it "allows the request body to be rewritten" do
		@req.body = 'something else'
		@req.body.should == 'something else'
	end


	describe "header convenience methods" do

		before( :each ) do
			@req.headers.merge!(
				'Content-length' => '28113',
				'Content-type' => 'application/x-pdf',
				'Content-encoding' => 'gzip'
			)
		end

		it "provides a convenience method for fetching the 'Content-type' header" do
			@req.content_type.should == 'application/x-pdf'
		end

		it "provides a convenience method for resetting the 'Content-type' header" do
			@req.content_type = 'application/json'
			@req.content_type.should == 'application/json'
		end

		it "provides a convenience method for fetching the 'Content-encoding' header" do
			@req.content_encoding.should == 'gzip'
		end

		it "provides a convenience method for resetting the 'Content-encoding' header" do
			@req.content_encoding = 'identity'
			@req.content_encoding.should == 'identity'
		end

		it "provides a convenience method for fetching the request's Content-length header" do
			@req.content_length.should == 28113
		end

		it "returns 0 as the content_length if the request doesn't have a Content-length header" do
			@req.headers.delete( :content_length )
			@req.content_length.should == 0
		end

		it "raises an exception if the Content-length header contains something other than an integer" do
			@req.headers.content_length = 'Lots'
			expect {
				@req.content_length
			}.to raise_error( ArgumentError, /invalid value for integer/i )
		end

		it "provides a convenience method for fetching the requestor's IP address" do
			@req.headers.merge!(
				'X-Forwarded-For' => '127.0.0.1'
			)
			@req.remote_ip.to_s.should == '127.0.0.1'
		end

		it "fetching the requestor's IP address even when travelling via proxies" do
			@req.headers.merge!(
				'X-Forwarded-For' => [ '127.0.0.1', '8.8.8.8', '4.4.4.4' ]
			)
			@req.remote_ip.to_s.should == '127.0.0.1'
		end

	end

end

