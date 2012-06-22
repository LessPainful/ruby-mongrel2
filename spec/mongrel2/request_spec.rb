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
require 'tmpdir'
require 'tempfile'

require 'spec/lib/helpers'

require 'mongrel2'
require 'mongrel2/request'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::Request do

	before( :all ) do
		setup_logging( :fatal )
		@factory = Mongrel2::RequestFactory.new( route: '/form' )
	end

	after( :all ) do
		reset_logging()
	end


	it "can parse a request message" do

		message = make_request()
		req = Mongrel2::Request.parse( message )

		req.should be_a( Mongrel2::Request )
		req.sender_id.should == TEST_UUID
		req.conn_id.should == TEST_ID

		req.headers.should be_a( Mongrel2::Table )
		req.headers['Host'].should == TEST_HEADERS['host']
	end

	it "can parse a request message with TNetstring headers" do

		message = make_tn_request()
		req = Mongrel2::Request.parse( message )

		req.should be_a( Mongrel2::Request )
		req.sender_id.should == TEST_UUID
		req.conn_id.should == TEST_ID

		req.headers.should be_a( Mongrel2::Table )
		req.headers.host.should == TEST_HEADERS['host']
	end

	it "can parse a request message with a JSON body" do

		message = make_json_request()
		req = Mongrel2::Request.parse( message )

		req.should be_a( Mongrel2::JSONRequest )
		req.sender_id.should == TEST_UUID
		req.conn_id.should == TEST_ID

		req.headers.should be_a( Mongrel2::Table )
		req.headers.path.should == TEST_JSON_PATH

		req.data.should == TEST_JSON_BODY
	end

	it "raises an UnhandledMethodError with the name of the method for METHOD verbs that " +
	   "don't look like HTTP ones" do

		message = make_request( :headers => {'METHOD' => '!DIVULGE'} )
		expect { Mongrel2::Request.parse(message) }.to raise_error( Mongrel2::UnhandledMethodError, /!DIVULGE/ )
	end

	it "knows what kind of response it should return" do
		Mongrel2::Request.response_class.should == Mongrel2::Response
	end


	describe "instances" do

		before( :each ) do
			message = make_json_request() # HTTPRequest overrides the #response method
			@req = Mongrel2::Request.parse( message )
		end

		it "can return an appropriate response instance for themselves" do
			result = @req.response
			result.should be_a( Mongrel2::Response )
			result.sender_id.should == @req.sender_id
			result.conn_id.should == @req.conn_id
		end

		it "remembers its response if it's already made one" do
			@req.response.should equal( @req.response )
		end

		it "allows the entity body to be replaced by assigning a String" do
			@req.body = 'something else'
			@req.body.should be_a( StringIO )
			@req.body.string.should == 'something else'
		end

		it "doesn't try to wrap non-stringish entity body replacements in a StringIO" do
			testobj = Object.new
			@req.body = testobj
			@req.body.should be( testobj )
		end

	end


	describe "content-type charset support" do

		it "uses the charset in the content-type header, if present" do
			body = "some data".encode( 'binary' )
			req = @factory.post( '/form', body, content_type: 'text/plain; charset=iso-8859-1' )

			req.body.string.encoding.should be( Encoding::ISO_8859_1 )
		end

		it "keeps the data as ascii-8bit if no charset is in the content-type header" do
			body = "some data".encode( 'binary' )
			req = @factory.post( '/form', body, content_type: 'application/octet-stream' )

			req.body.string.encoding.should be( Encoding::ASCII_8BIT )
		end

		it "keeps the data as ascii-8bit if there is no content-type header" do
			body = "some data".encode( 'binary' )
			req = @factory.post( '/form', body )

			req.body.string.encoding.should be( Encoding::ASCII_8BIT )
		end

	end

	describe "framework support" do

		before( :all ) do
			@oldtypes = Mongrel2::Request.request_types.dup
			@original_default_proc = Mongrel2::Request.request_types.default_proc
		end

		before( :each ) do
			Mongrel2::Request.request_types.default_proc = @original_default_proc
			Mongrel2::Request.request_types.clear
		end

		after( :all ) do
			Mongrel2::Request.request_types.default_proc = @original_default_proc
			Mongrel2::Request.request_types.replace( @oldtypes )
		end


		it "includes a mechanism for overriding the default Request subclass" do
			subclass = Class.new( Mongrel2::Request ) do
				register_request_type self, :__default
			end

			Mongrel2::Request.subclass_for_method( 'GET' ).should == subclass
			Mongrel2::Request.subclass_for_method( 'POST' ).should == subclass
			Mongrel2::Request.subclass_for_method( 'JSON' ).should == subclass
		end

		it "includes a mechanism for overriding the Request subclass for a particular request " +
		   "method" do
			subclass = Class.new( Mongrel2::Request ) do
				register_request_type self, :GET
			end

			Mongrel2::Request.subclass_for_method( 'GET' ).should == subclass
			Mongrel2::Request.subclass_for_method( 'POST' ).should_not == subclass
			Mongrel2::Request.subclass_for_method( 'JSON' ).should_not == subclass
		end

		it "clears any cached method -> subclass lookups when the default subclass changes" do
			Mongrel2::Request.subclass_for_method( 'OPTIONS' ) # cache OPTIONS -> Mongrel2::Request

			subclass = Class.new( Mongrel2::Request ) do
				register_request_type self, :__default
			end

			Mongrel2::Request.subclass_for_method( 'OPTIONS' ).should == subclass
		end

	end


	describe "async upload support" do

		before( :all ) do
			setup_config_db()
			Mongrel2::Config::Server.create(
				 uuid:         Mongrel2::RequestFactory::DEFAULT_TEST_UUID,
				 access_log:   'access.log',
				 error_log:    'error.log',
				 pid_file:     '/var/run/mongrel2.pid',
				 default_host: 'localhost',
				 port:         663,
				 chroot:       Dir.tmpdir
			  )
		end

		before( :each ) do
			@spoolfile = Tempfile.new( 'mongrel2.upload', Dir.tmpdir )
			@spoolfile.print( File.read(__FILE__) )
			@spoolpath = @spoolfile.path.slice( Dir.tmpdir.length + 1..-1 )
		end

		it "knows if it's an 'async upload started' notification" do
			req = @factory.post( '/form', '', x_mongrel2_upload_start: @spoolpath )

			req.should be_upload_started()
			req.should_not be_upload_done()
		end

		it "knows if it's an 'async upload done' notification" do
			req = @factory.post( '/form', '',
				x_mongrel2_upload_start: @spoolpath,
				x_mongrel2_upload_done: @spoolpath )

			req.should_not be_upload_started()
			req.should be_upload_done()
			req.should be_valid_upload()
		end

		it "knows if it's not a valid 'async upload done' notification" do
			req = @factory.post( '/form', '',
				x_mongrel2_upload_start: @spoolpath,
				x_mongrel2_upload_done: '/etc/passwd' )

			req.should_not be_upload_started()
			req.should be_upload_done()
			req.should_not be_valid_upload()
		end

		it "raises an exception if the uploaded file fetched with mismatched headers" do
			req = @factory.post( '/form', '',
				x_mongrel2_upload_start: @spoolpath,
				x_mongrel2_upload_done: '/etc/passwd' )

			expect {
				req.uploaded_file
			}.to raise_error( Mongrel2::UploadError, /upload headers/i )
		end

		it "can return a Pathname object for the uploaded file if it's valid" do
			req = @factory.post( '/form', '',
				x_mongrel2_upload_start: @spoolpath,
				x_mongrel2_upload_done:  @spoolpath )

			req.should be_valid_upload()

			req.uploaded_file.should be_a( Pathname )
			req.uploaded_file.to_s.should == @spoolfile.path
		end

		it "sets the body of the request to the uploaded File if it's valid" do
			req = @factory.post( '/form', '',
				x_mongrel2_upload_start: @spoolpath,
				x_mongrel2_upload_done:  @spoolpath )

			req.should be_valid_upload()

			req.body.should be_a( File )
			req.body.path.should == @spoolfile.path
		end

	end

end

