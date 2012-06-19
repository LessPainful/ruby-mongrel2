#!/usr/bin/env ruby
#encoding: utf-8

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'
require 'tnetstring'
require 'securerandom'

require 'spec/lib/helpers'

require 'mongrel2'
require 'mongrel2/websocket'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::WebSocket do

	before( :all ) do
		setup_logging( :fatal )
		@factory = Mongrel2::WebSocketFrameFactory.new( route: '/websock' )
	end

	after( :all ) do
		reset_logging()
	end

	# Data for testing payload of binary frames
	BINARY_DATA =
		"\a\xBD\xB3\xFE\x87\xEB\xA9\x0En2q\xCE\x85\xAF)\x88w_d\xD6M" +
		"\x9E\xAF\xCB\x89\x8F\xC8\xA0\x80ZL+\a\x9C\xF7{`\x9E'\xCF\xD9" +
		"\xE8\xA5\x9C\xF7T\xE2\xDD\xF5\xE9\x14\x1F,?\xD2\nQ\f\x06\x96" +
		"\x19\xB7\x06\x9F\xCD+*\x01\xC7\x98\xFE\x8A\x81\x04\xFF\xA7.J" +
		"\xF1\x9F\x9E\xEB$<;\x99>q\xBA\x12\xB3&i\xCCaE}\xAA\x87>ya\x0E" +
		"\xB0n\xD8lN\xE5\b\x83\xBB\x1D1\xFD\e\x84\xC1\xB4\x99\xC7\xCA" +
		"\xF8}C\xF2\xC6\x04\xA208\xA1\xCF\xB9\xFF\xF2\x9C~mbi\xBC\xE0" +
		"\xBE\xFER\xB5B#\xF1Z^\xB6\x80\xD2\x8E=t\xC6\x86`\xFAY\xD9\x01" +
		"\xBF\xA7\x88\xE1rf?C\xB8XC\xEF\x9F\xB1j,\xC7\xE4\x9E\x86)7\"f0" +
		"\xA0FH\xFC\x99\xCA\xB3D\x06ar\x9C\xEC\xE9\xAEj:\xFD\x1C\x06H\xF0" +
		"\xF1w~\xEC\r\x7F\x00\xED\xD88\x81\xF0/\x99\xD7\x9D\xA9C\x06\xEF" +
		"\x9B\xF3\x17\a\xDB\v{\e\xA3\tKTPV\xB8\xCB\xBB\xC9\x87f\\\xD0\x165"
	BINARY_DATA.force_encoding( Encoding::ASCII_8BIT )


	describe 'Frame' do

		it "is the registered request type for WEBSOCKET requests" do
			Mongrel2::Request.request_types[:WEBSOCKET].should == Mongrel2::WebSocket::Frame
		end

		it "knows that its FIN flag is not set if its FLAG header doesn't include that bit" do
			frame = @factory.text( '/websock', 'Hello!' )
			frame.flags ^= ( frame.flags & Mongrel2::WebSocket::FIN_FLAG )
			frame.should_not be_fin()
		end

		it "knows that its FIN flag is set if its FLAG header includes that bit" do
			frame = @factory.text( '/websock', 'Hello!', :fin )
			frame.should be_fin()
		end

		it "can unset its FIN flag" do
			frame = @factory.text( '/websock', 'Hello!', :fin )
			frame.fin = false
			frame.should_not be_fin()
		end

		it "can set its FIN flag" do
			frame = @factory.text( '/websock', 'Hello!' )
			frame.fin = true
			frame.should be_fin()
		end

		it "knows that its opcode is continuation if its opcode is 0x0" do
			@factory.continuation( '/websock' ).opcode.should == :continuation
		end

		it "knows that is opcode is 'text' if its opcode is 0x1" do 
			@factory.text( '/websock', 'Hello!' ).opcode.should == :text
		end

		it "knows that is opcode is 'binary' if its opcode is 0x2" do 
			@factory.binary( '/websock', 'Hello!' ).opcode.should == :binary
		end

		it "knows that is opcode is 'close' if its opcode is 0x8" do 
			@factory.close( '/websock' ).opcode.should == :close
		end

		it "knows that is opcode is 'ping' if its opcode is 0x9" do 
			@factory.ping( '/websock' ).opcode.should == :ping
		end

		it "knows that is opcode is 'pong' if its opcode is 0xA" do 
			@factory.pong( '/websock' ).opcode.should == :pong
		end

		it "knows that its RSV1 flag is set if its FLAG header includes that bit" do
			@factory.ping( '/websock', 'test', :rsv1 ).should be_rsv1()
		end

		it "knows that its RSV2 flag is set if its FLAG header includes that bit" do
			@factory.ping( '/websock', 'test', :rsv2 ).should be_rsv2()
		end

		it "knows that its RSV3 flag is set if its FLAG header includes that bit" do
			@factory.ping( '/websock', 'test', :rsv3 ).should be_rsv3()
		end

		it "knows that one of its RSV flags is set if its FLAG header includes RSV1" do
			@factory.ping( '/websock', 'test', :rsv1 ).should have_rsv_flags()
		end

		it "knows that one of its RSV flags is set if its FLAG header includes RSV2" do
			@factory.ping( '/websock', 'test', :rsv2 ).should have_rsv_flags()
		end

		it "knows that one of its RSV flags is set if its FLAG header includes RSV3" do
			@factory.ping( '/websock', 'test', :rsv3 ).should have_rsv_flags()
		end

		it "knows that no RSV flags are set if its FLAG header doesn't have any RSV bits" do
			@factory.ping( '/websock', 'test' ).should_not have_rsv_flags()
		end

		it "can create a response WebSocket::Frame for itself" do
			frame = @factory.text( '/websock', "Hi, here's a message!", :fin )

			result = frame.response

			result.should be_a( Mongrel2::WebSocket::Frame )
			result.sender_id.should == frame.sender_id
			result.conn_id.should == frame.conn_id
			result.opcode.should == :text

			result.payload.rewind
			result.payload.read.should == ''
		end

		it "creates PONG responses with the same payload for PING frames" do
			frame = @factory.ping( '/websock', "WOO" )

			result = frame.response

			result.should be_a( Mongrel2::WebSocket::Frame )
			result.sender_id.should == frame.sender_id
			result.conn_id.should == frame.conn_id
			result.opcode.should == :pong

			result.payload.rewind
			result.payload.read.should == 'WOO'
		end

		it "allows header flags and/or opcode to be specified when creating a response" do
			frame = @factory.text( '/websock', "some bad data" )

			result = frame.response( :close, :fin )

			result.should be_a( Mongrel2::WebSocket::Frame )
			result.sender_id.should == frame.sender_id
			result.conn_id.should == frame.conn_id
			result.opcode.should == :close
			result.should be_fin()

			result.payload.rewind
			result.payload.read.should == ''
		end

		it "can be streamed in chunks instead of read all at once" do
			data = BINARY_DATA * 256
			binary = @factory.binary( '/websock', data, :fin )

			binary.chunksize = 16
			binary.each_chunk.to_a[0,2].should == [
				"\x82\x7F\x00\x00\x00\x00\x00\x01\x00\x00\a\xBD\xB3\xFE\x87\xEB".force_encoding('binary'),
				"\xA9\x0En2q\xCE\x85\xAF)\x88w_d\xD6M\x9E".force_encoding('binary'),
			]
		end

	end


	describe "a WebSocket text frame" do

		before( :each ) do
			@frame = @factory.text( '/websock', '', :fin )
		end

		it "automatically transcodes its payload to UTF8" do
			text = "Стрелке!".encode( Encoding::KOI8_U )
			@frame << text

			# 2-byte header
			@frame.bytes.to_a[ 2..-1 ].should ==
				[0xD0, 0xA1, 0xD1, 0x82, 0xD1, 0x80, 0xD0, 0xB5, 0xD0, 0xBB, 0xD0,
				 0xBA, 0xD0, 0xB5, 0x21]
		end

	end


	describe "a WebSocket binary frame" do
		before( :each ) do
			@frame = @factory.binary( '/websock', BINARY_DATA, :fin )
		end

		it "doesn't try to transcode non-UTF8 data" do
			# 4-byte header
			@frame.bytes.to_a[ 4, 16 ].should ==
				[ 0x07, 0xbd, 0xb3, 0xfe, 0x87, 0xeb, 0xa9, 0x0e, 0x6e, 0x32, 0x71,
				  0xce, 0x85, 0xaf, 0x29, 0x88 ]
		end
	end


	describe "a WebSocket close frame" do
		before( :each ) do
			@frame = @factory.close( '/websock' )
		end

		it "has convenience methods for setting its payload via integer status code" do
			@frame.set_status( CLOSE_BAD_DATA )
			@frame.payload.rewind
			@frame.payload.read.should == "%d %s\n" %
				[ CLOSE_BAD_DATA, CLOSING_STATUS_DESC[CLOSE_BAD_DATA] ]
		end

	end


	describe "WebSocket control frames" do
		before( :each ) do
			@frame = @factory.close( '/websock', "1002 Protocol error" )
		end


		it "raises an exception if its payload is bigger than 125 bytes" do
			@frame.body << "x" * 126
			expect {
				@frame.validate
			}.to raise_error( Mongrel2::WebSocket::FrameError, /cannot exceed 125 bytes/i )
		end

		it "raises an exception if it's fragmented" do
			@frame.fin = false
			expect {
				@frame.validate
			}.to raise_error( Mongrel2::WebSocket::FrameError, /fragmented/i )
		end

	end


	describe "RFC examples (the applicable ones, anyway)" do

		it "generates a single-frame unmasked text message correctly" do
			raw_response = @factory.text( '/websock', "Hello", :fin ).to_s
			raw_response.bytes.to_a.should == [ 0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f ]
			raw_response.encoding.should == Encoding::BINARY
		end

		it "generates both parts of a fragmented unmasked text message correctly" do
			first = @factory.text( '/websock', 'Hel' )
			last = @factory.continuation( '/websock', 'lo', :fin )

			first.bytes.to_a.should == [ 0x01, 0x03, 0x48, 0x65, 0x6c ]
			last.bytes.to_a.should == [ 0x80, 0x02, 0x6c, 0x6f ]
		end

		# The RFC's example is a masked response, but we're never a client, so never
		# generate masked payloads.
		it "generates a unmasked Ping request and (un)masked Ping response correctly" do
			ping = @factory.ping( '/websock', 'Hello' )
			pong = @factory.pong( '/websock', 'Hello' )

			ping.bytes.to_a.should == [ 0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f ]
			pong.bytes.to_a.should == [ 0x8a, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f ]
		end


		it "generates a 256-byte binary message in a single unmasked frame" do
			binary = @factory.binary( '/websock', BINARY_DATA, :fin )

			# 1 + 1 + 2
			binary.bytes.to_a[0,4].should == [ 0x82, 0x7E, 0x01, 0x00 ]
			binary.to_s[4..-1].should == BINARY_DATA
		end

		it "generates a 64KiB binary message in a single unmasked frame correctly" do
			data = BINARY_DATA * 256

			binary = @factory.binary( '/websock', data, :fin )

			# 1 + 1 + 8
			binary.bytes.to_a[0,10].should ==
				[ 0x82, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00 ]
			binary.to_s[10..-1].should == data
		end

	end

end

