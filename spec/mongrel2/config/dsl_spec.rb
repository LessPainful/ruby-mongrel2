#!/usr/bin/env ruby

BEGIN {
	require 'pathname'
	basedir = Pathname.new( __FILE__ ).dirname.parent.parent.parent

	libdir = basedir + "lib"

	$LOAD_PATH.unshift( basedir ) unless $LOAD_PATH.include?( basedir )
	$LOAD_PATH.unshift( libdir ) unless $LOAD_PATH.include?( libdir )
}

require 'rspec'

require 'spec/lib/helpers'

require 'mongrel2'
require 'mongrel2/config'


#####################################################################
###	C O N T E X T S
#####################################################################

describe Mongrel2::Config::DSL do

	include described_class

	before( :all ) do
		setup_logging( :fatal )
		setup_config_db()
	end

	before( :each ) do
		Mongrel2::Config::Server.truncate
		Mongrel2::Config::Host.truncate
		Mongrel2::Config::Route.truncate
		Mongrel2::Config::Filter.truncate
	end

	after( :all ) do
		reset_logging()
	end


	describe 'servers' do
		it "can generate a default server config using the 'server' declarative" do
			result = server '965A7196-99BC-46FA-945B-3478AE92BFB5'

			result.should be_a( Mongrel2::Config::Server )
			result.uuid.should == '965A7196-99BC-46FA-945B-3478AE92BFB5'
		end


		it "can generate a more-elaborate server config using the 'server' declarative with a block" do
			result = server '965A7196-99BC-46FA-945B-3478AE92BFB5' do
				name 'Intranet'
				chroot '/service/mongrel2'
				access_log '/var/log/access'
				error_log '/var/log/errors'
			end

			result.should be_a( Mongrel2::Config::Server )
			result.uuid.should == '965A7196-99BC-46FA-945B-3478AE92BFB5'
			result.name.should == 'Intranet'
			result.chroot.should == '/service/mongrel2'
			result.access_log.should == '/var/log/access'
			result.error_log.should == '/var/log/errors'
		end
	end

	describe 'hosts' do

		it "can add a host to a server config with the 'host' declarative" do
			result = server '965A7196-99BC-46FA-945B-3478AE92BFB5' do

				host 'localhost'

			end

			result.should be_a( Mongrel2::Config::Server )
			result.hosts.should have( 1 ).member
			host = result.hosts.first

			host.should be_a( Mongrel2::Config::Host )
			host.name.should == 'localhost'
		end

		it "can add several elaborately-configured hosts to a server via a block" do
			result = server '965A7196-99BC-46FA-945B-3478AE92BFB5' do

				host 'brillianttaste' do
					matching '*.brillianttasteinthefoodmouth.com'

					route '/images', directory( 'var/www/images/', 'index.html', 'image/jpeg' )
					route '/css', directory( 'var/www/css/', 'index.html', 'text/css' )
					route '/vote', proxy( 'localhost', 6667 )
					route '/admin', handler(
						'tcp://127.0.0.1:9998',
						'D613E7EE-E2EB-4699-A200-5C8ECAB45D5E'
					)

					dir_handler = handler(
						'tcp://127.0.0.1:9996',
						'B7EFA46D-FEE4-432B-B80F-E8A9A2CC6FDB',
						'tcp://127.0.0.1:9992',
						'protocol' => 'tnetstring'
					)
					route '@directory', dir_handler
					route '/directory', dir_handler
				end

				host 'deveiate.org' do
					route '', directory('usr/local/deveiate/www/public/', 'index.html')
				end

			end

			result.should be_a( Mongrel2::Config::Server )
			result.hosts.should have( 2 ).members
			host1, host2 = result.hosts

			host1.should be_a( Mongrel2::Config::Host )
			host1.name.should == 'brillianttaste'
			host1.matching.should == '*.brillianttasteinthefoodmouth.com'
			host1.routes.should have( 6 ).members
			host1.routes.should all_be_a( Mongrel2::Config::Route )

			host1.routes[0].path.should == '/images'
			host1.routes[0].target.should be_a( Mongrel2::Config::Directory )
			host1.routes[0].target.base.should == 'var/www/images/'

			host1.routes[1].path.should == '/css'
			host1.routes[1].target.should be_a( Mongrel2::Config::Directory )
			host1.routes[1].target.base.should == 'var/www/css/'

			host1.routes[2].path.should == '/vote'
			host1.routes[2].target.should be_a( Mongrel2::Config::Proxy )
			host1.routes[2].target.addr.should == 'localhost'
			host1.routes[2].target.port.should == 6667

			host1.routes[3].path.should == '/admin'
			host1.routes[3].target.should be_a( Mongrel2::Config::Handler )
			host1.routes[3].target.send_ident.should == 'D613E7EE-E2EB-4699-A200-5C8ECAB45D5E'
			host1.routes[3].target.send_spec.should == 'tcp://127.0.0.1:9998'
			host1.routes[3].target.recv_ident.should == ''
			host1.routes[3].target.recv_spec.should == 'tcp://127.0.0.1:9997'

			host1.routes[4].path.should == '@directory'
			host1.routes[4].target.should be_a( Mongrel2::Config::Handler )
			host1.routes[4].target.send_ident.should == 'B7EFA46D-FEE4-432B-B80F-E8A9A2CC6FDB'
			host1.routes[4].target.send_spec.should == 'tcp://127.0.0.1:9996'
			host1.routes[4].target.recv_spec.should == 'tcp://127.0.0.1:9992'
			host1.routes[4].target.recv_ident.should == ''
			host1.routes[4].target.protocol.should == 'tnetstring'

			host1.routes[5].path.should == '/directory'
			host1.routes[5].target.should == host1.routes[4].target

			host2.should be_a( Mongrel2::Config::Host )
			host2.name.should == 'deveiate.org'
			host2.routes.should have( 1 ).member
			host2.routes.first.should be_a( Mongrel2::Config::Route )
		end


	end

	describe 'settings' do

		before( :all ) do
			@ids = Mongrel2::Config::Setting.map( :id )
		end

		after( :each ) do
			Mongrel2::Config::Setting.dataset.filter( ~:id => @ids ).delete
		end

		it "can set the expert tweakable settings en masse" do
			result = settings(
				"zeromq.threads"         => 8,
				"upload.temp_store"      => "/home/zedshaw/projects/mongrel2/tmp/upload.XXXXXX", 
				"upload.temp_store_mode" => "0666" 
			)

			result.should be_an( Array )
			result.should have( 3 ).members
			result.should all_be_a( Mongrel2::Config::Setting )
			result[0].key.should == 'zeromq.threads'
			result[0].value.should == '8'
			result[1].key.should == 'upload.temp_store'
			result[1].value.should == '/home/zedshaw/projects/mongrel2/tmp/upload.XXXXXX'
			result[2].key.should == 'upload.temp_store_mode'
			result[2].value.should == '0666'
		end

		it "can set a single expert setting" do
			result = setting "zeromq.threads", 16
			result.should be_a( Mongrel2::Config::Setting )
			result.key.should == 'zeromq.threads'
			result.value.should == '16'
		end

	end

	describe 'mimetypes' do

		it "can set new mimetype mappings en masse" do
			result = mimetypes(
				'.md'      => 'text/x-markdown',
				'.textile' => 'text/x-textile'
			)

			result.should be_an( Array )
			result.should have( 2 ).members
			result.should all_be_a( Mongrel2::Config::Mimetype )
			result[0].extension.should == '.md'
			result[0].mimetype.should == 'text/x-markdown'
			result[1].extension.should == '.textile'
			result[1].mimetype.should == 'text/x-textile'
		end

		it "can set a single mimetype mapping" do
			result = mimetype '.tmpl', 'text/x-inversion-template'
			result.should be_a( Mongrel2::Config::Mimetype )
			result.extension.should == '.tmpl'
			result.mimetype.should == 'text/x-inversion-template'
		end

	end

	describe 'filters' do

		it "can add a filter to a server" do
			result = server '965A7196-99BC-46FA-945B-3478AE92BFB5' do
				filter '/usr/lib/mongrel2/null.so'
			end

			result.filters.should have( 1 ).member
			result.filters.first.should be_a( Mongrel2::Config::Filter )
			result.filters.first.settings.should == {}
		end

		it "can add a filter with settings to a server" do
			result = server '965A7196-99BC-46FA-945B-3478AE92BFB5' do
				filter '/usr/lib/mongrel2/null.so',
					extensions: ["*.html", "*.txt"],
					min_size: 1000
			end

			result.filters.should have( 1 ).member
			result.filters.first.should be_a( Mongrel2::Config::Filter )
			result.filters.first.settings.should ==
				{ 'extensions' => ["*.html", "*.txt"], 'min_size' => 1000 }
		end

	end

end

