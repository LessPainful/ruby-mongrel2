#!/usr/bin/env ruby

require 'pathname'
require 'tmpdir'

# The Mongrel config used by the examples. Load it with:
#
#   m2sh.rb -c examples.sqlite load examples/config.rb
#

examples_dir = Pathname( __FILE__ ).dirname
basedir = examples_dir.parent
upload_dir = Pathname( Dir.tmpdir )

# samples server
server 'examples' do

	name         'Examples'
	default_host 'localhost'

	access_log   '/logs/access.log'
	error_log    '/logs/error.log'
	chroot       '/var/mongrel2'
	pid_file     '/var/run/mongrel2.pid'

	bind_addr    '0.0.0.0'
	port         8113

	# your main host
	host 'localhost' do

		route '/', directory( "#{basedir}/data/mongrel2/", 'bootstrap.html', 'text/html' )
		route '/source', directory( "#{basedir}/examples/", 'README.txt', 'text/plain' )

		# Handlers
		dumper = handler( 'tcp://127.0.0.1:9997', 'request-dumper', protocol: 'tnetstring' )
		route '/hello', handler( 'tcp://127.0.0.1:9999',  'helloworld-handler' )
		route '/async-upload', handler( 'tcp://127.0.0.1:9950',  'async-upload' )
		route '/dump', dumper
		route '/ws', handler( 'tcp://127.0.0.1:9995', 'ws-echo' )
		route '@js', dumper
		route '<xml', dumper

	end

end

setting 'zeromq.threads', 1
setting 'limits.content_length', 4096
setting 'control_port', 'ipc://var/run/control'
setting 'upload.temp_store', upload_dir + 'mongrel2.upload.XXXXXX'

mkdir_p 'var/run'
mkdir_p 'logs'
mkdir_p '/tmp/mongrel2-uploads'

puts "Upload dir is: #{upload_dir}"
