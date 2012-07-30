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
require 'mongrel2/control'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::Control do

	before( :all ) do
		setup_logging( :fatal )
	end

	before( :each ) do
		@ctx = double( "ZMQ::Context" )
		@socket = double( "ZMQ REQ socket", :connect => nil, :setsockopt => nil )
		@ctx.stub( :socket ).with( ZMQ::REQ ).and_return( @socket )

		Mongrel2.instance_variable_set( :@zmq_ctx, @ctx )

		FileTest.stub( :socket? ).with( 'var/run/control' ). and_return( true )

		@control = Mongrel2::Control.new( 'ipc://var/run/control' )
	end

	after( :all ) do
		Mongrel2.instance_variable_set( :@zmq_ctx, nil )
		reset_logging()
	end


	it "sends a 'stop' command to the control port when #stop is called" do
		@socket.should_receive( :send ).with( "10:4:stop,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "59:7:headers,6:3:msg,]4:rows,29:25:21:signal sent to server,]]}" )
		@control.stop.should == [{ :msg => "signal sent to server" }]
	end

	it "sends a 'reload' command to the control port when #reload is called" do
		@socket.should_receive( :send ).with( "12:6:reload,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "59:7:headers,6:3:msg,]4:rows,29:25:21:signal sent to server,]]}" )
		@control.reload.should == [{ :msg => "signal sent to server" }]
	end

	it "sends a 'terminate' command to the control port when #terminate is called" do
		@socket.should_receive( :send ).with( "15:9:terminate,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "59:7:headers,6:3:msg,]4:rows,29:25:21:signal sent to server,]]}" )
		@control.terminate.should == [{ :msg => "signal sent to server" }]
	end

	it "sends a 'help' command to the control port when #help is called" do
		@socket.should_receive( :send ).with( "10:4:help,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "416:7:headers,14:4:name,4:help,]4:rows,376:35:4:stop" +
			            ",24:stop the server (SIGINT),]30:6:reload,17:reload " +
			            "the server,]23:4:help,12:this command,]37:12:control" +
			            "_stop,17:stop control port,]28:4:kill,17:kill a conn" +
			            "ection,]41:6:status,28:status, what=['net'|'tasks']," +
			            "]46:9:terminate,30:terminate the server (SIGTERM),]2" +
			            "8:4:time,17:the server's time,]28:4:uuid,17:the serv" +
			            "er's uuid,]40:4:info,29:information about this serve" +
			            "r,]]}" )
		@control.help.should == [
			{:name => "stop",         :help => "stop the server (SIGINT)"},
			{:name => "reload",       :help => "reload the server"},
			{:name => "help",         :help => "this command"},
			{:name => "control_stop", :help => "stop control port"},
			{:name => "kill",         :help => "kill a connection"},
			{:name => "status",       :help => "status, what=['net'|'tasks']"},
			{:name => "terminate",    :help => "terminate the server (SIGTERM)"},
			{:name => "time",         :help => "the server's time"},
			{:name => "uuid",         :help => "the server's uuid"},
			{:name => "info",         :help => "information about this server"}
		]
	end

	it "sends a 'uuid' command to the control port when #uuid is called" do
		@socket.should_receive( :send ).with( "10:4:uuid,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "75:7:headers,7:4:uuid,]4:rows,44:40:36:34D8E57C-3E91" +
			            "-4F24-9BBE-0B53C1827CB4,]]}" )
		@control.uuid.should == [{ :uuid => '34D8E57C-3E91-4F24-9BBE-0B53C1827CB4' }]
	end

	it "sends an 'info' command to the control port when #info is called" do
		@socket.should_receive( :send ).with( "10:4:info,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "260:7:headers,92:4:port,9:bind_addr,4:uuid,6:chroot," +
			            "10:access_log,9:error_log,8:pid_file,16:default_host" +
			            "name,]4:rows,142:137:4:8113#7:0.0.0.0,36:34D8E57C-3E" +
			            "91-4F24-9BBE-0B53C1827CB4,2:./,18:.//logs/access.log" +
			            ",15:/logs/error.log,18:./run/mongrel2.pid,9:localhos" +
			            "t,]]}" )
		@control.info.should == [{
			:port             => 8113,
			:bind_addr        => "0.0.0.0",
			:uuid             => "34D8E57C-3E91-4F24-9BBE-0B53C1827CB4",
			:chroot           => "./",
			:access_log       => ".//logs/access.log",
			:error_log        => "/logs/error.log",
			:pid_file         => "./run/mongrel2.pid",
			:default_hostname => "localhost"
		}]
	end

	it "sends a 'status' command with a 'what' option set to 'tasks' to the control port " +
	   "when #tasklist is called" do

		@socket.should_receive( :send ).with( "28:6:status,15:4:what,5:tasks,}]" )
		@socket.should_receive( :recv ).
			and_return( "343:7:headers,38:2:id,6:system,4:name,5:state,6:status," +
			            "]4:rows,279:38:1:1#5:false!6:SERVER,7:read fd,4:idle,]5" +
			            "1:1:2#5:false!12:Handler_task,12:read handler,4:idle,]5" +
			            "1:1:3#5:false!12:Handler_task,12:read handler,4:idle,]4" +
			            "8:1:4#5:false!7:control,12:read handler,7:running,]31:1" +
			            ":5#5:false!6:ticker,0:,4:idle,]36:1:6#4:true!6:fdtask,5" +
			            ":yield,5:ready,]]}" )
		@control.tasklist.should == [
			{:id=>1, :system=>false, :name=>"SERVER",       :state=>"read fd",      :status=>"idle"},
			{:id=>2, :system=>false, :name=>"Handler_task", :state=>"read handler", :status=>"idle"},
			{:id=>3, :system=>false, :name=>"Handler_task", :state=>"read handler", :status=>"idle"},
			{:id=>4, :system=>false, :name=>"control",      :state=>"read handler", :status=>"running"},
			{:id=>5, :system=>false, :name=>"ticker",       :state=>"",             :status=>"idle"},
			{:id=>6, :system=>true,  :name=>"fdtask",       :state=>"yield",        :status=>"ready"}
		]
	end

	it "sends an 'status' command with a 'what' option set to 'net' to the control port " +
	   "when #conn_status is called" do

		@socket.should_receive( :send ).with( "26:6:status,13:4:what,3:net,}]" )
		@socket.should_receive( :recv ).
			and_return( "150:7:headers,86:2:id,2:fd,4:type,9:last_ping,9:last_read," +
			            "10:last_write,10:bytes_read,13:bytes_written,]4:rows,39:35" +
			            ":1:2#2:38#1:1#1:0#1:0#1:0#3:405#1:0#]]}" )
		@control.conn_status.should == [
			{:id=>2, :fd=>38, :type=>1, :last_ping=>0, :last_read=>0, :last_write=>0,
				:bytes_read=>405, :bytes_written=>0}
		]
	end

	it "sends a 'time' command to the control port when #time is called" do
		@socket.should_receive( :send ).with( "10:4:time,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "49:7:headers,7:4:time,]4:rows,18:14:10:1315532674,]]}" )
		@control.time.should == Time.at( 1315532674 )
	end

	it "sends a 'kill' command with an ID equal to the argument to the control port when #kill " +
	   "is called" do
		@socket.should_receive( :send ).with( "19:4:kill,9:2:id,1:0#}]" )
		@socket.should_receive( :recv ).and_return( "40:7:headers,9:6:status,]4:rows,8:5:2:OK,]]}" )
		@control.kill( 0 ).should == [{ :status => "OK" }]
	end

	it "sends a 'control_stop' command to the control port when #info is called" do
		@socket.should_receive( :send ).with( "19:12:control_stop,0:}]" )
		@socket.should_receive( :recv ).
			and_return( "63:7:headers,6:3:msg,]4:rows,33:29:25:stopping the control port,]]}" )
		@control.control_stop.should == [{:msg => "stopping the control port"}]
	end


	it "raises an exception if the server responds with an error" do
		@socket.should_receive( :send ).with( "19:4:kill,9:2:id,1:0#}]" )
		@socket.should_receive( :recv ).
			and_return( "61:4:code,16:INVALID_ARGUMENT,5:error,22:Invalid argument type.,}" )

		expect {
			@control.kill( 0 )
		}.to raise_error( Mongrel2::ControlError, /invalid argument type/i )
	end

end

