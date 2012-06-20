#!/usr/bin/env ruby

require 'pathname'
require 'loggability'
require 'mongrel2/config'
require 'mongrel2/handler'

require 'inversion'

# A handler that just dumps the request it gets from Mongrel2
class RequestDumper < Mongrel2::Handler

	TEMPLATE_DIR = Pathname( __FILE__ ).dirname
	Inversion::Template.configure( :template_paths => [TEMPLATE_DIR] )

	### Pre-load the template before running.
	def initialize( * )
		super
		@template = Inversion::Template.load( 'request-dumper.tmpl' )
		$SAFE = 1
	end


	### Handle a request
	def handle( request )
		template = @template.dup
		response = request.response

		template.request = request
		template.title = "Ruby-Mongrel2 Request Dumper"
		template.safelevel = $SAFE

		response.status = 200
		response.headers.content_type = 'text/html'
		response.puts( template )

		response
	end

end # class RequestDumper

Loggability.level = :debug
Loggability[ Inversion ].level = :info

# Point to the config database, which will cause the handler to use
# its ID to look up its own socket info.
Mongrel2::Config.configure( :configdb => 'examples.sqlite' )
RequestDumper.run( 'request-dumper' )

