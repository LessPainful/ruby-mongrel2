#!/usr/bin/env ruby

require 'erb'
require 'loggability'
require 'mongrel2/config'
require 'mongrel2/handler'

# A example of how to allow Mongrel2's async uploads.
class AsyncUploadHandler < Mongrel2::Handler

	# App ID
	ID = 'async-upload'

	### Load up the ERB template from the DATA section on instantiation.
	def initialize( * )
		super
		@template = self.load_template
	end


	### Load the ERB template from this file's DATA section.
	def load_template
		raw = IO.read( __FILE__ ).split( /^__END__$/m, 2 ).last
		return ERB.new( raw, nil, '<%>' )
	end


	### Mongrel2 async upload callback -- allow uploads to proceed.
	def handle_upload_start( request )
		self.log.info "Upload started: %s" % [ request.header.x_mongrel2_upload_start ]
		return nil # Do nothing
	end


	### Mongrel2 async upload callback -- finish the upload.
	def handle_upload_done( request )
		self.log.warn "Upload finished: %s (%0.2fK, %s)" %
			[ request.uploaded_file, request.content_length, request.content_type ]

		response = request.response
		response.puts "Upload complete: %s" % [ request.uploaded_file ]
		response.content_type = 'text/plain'

		return response
	rescue Mongrel2::UploadError => err
		self.log.error "%s when finishing an upload: %s" % [ err.class, err.message ]
		self.log.debug { err.backtrace.join("\n\t") }

		finish_with HTTP::BAD_REQUEST, 'malformed upload headers'
	end


	### Regular request -- show the upload form.
	def handle( request )
		# If it's the 'upload started' notification, use that handler method
		if request.upload_started?
			return self.handle_upload_start( request )

		# If it's a finished upload, use that handler method
		elsif request.upload_done?
			return self.handle_upload_done( request )

		else
			response = request.response

			settings = Mongrel2::Config.settings

			response.headers.content_type = 'text/html'
			response.puts( @template.result(binding()) )

			return response
		end
	end

end # class HelloWorldHandler

configdb = ARGV.shift || 'examples.sqlite'

# Log to a file instead of STDERR for a bit more speed.
# Loggability.output_to( 'hello-world.log' )
Loggability.level = :debug

# Point to the config database, which will cause the handler to use
# its ID to look up its own socket info.
Mongrel2::Config.configure( configdb: configdb )
AsyncUploadHandler.run( 'async-upload' )

__END__
<!DOCTYPE html>
<html lang="en">
<head>
	<title>Ruby-Mongrel2 Async Upload Demo</title>
	<meta charset="utf-8">
</head>

<body>

	<h1>Ruby-Mongrel2 Async Upload Demo</h1>

	<form action="<%= request.headers.uri %>" method="post" accept-charset="utf-8"
		enctype="multipart/form-data">

		<label for="file">Choose a file</label>
		<input type="file" name="uploaded-file" value="">

		<p>Upload will be async if it's larger than:
			<%= settings['limits.content_length'] %> bytes.</p>

		<p><input type="submit" value="Upload &rarr;"></p>
	</form>

</body>
</html>
