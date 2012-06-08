#!/usr/bin/ruby
#encoding: utf-8

require 'pathname'
require 'mongrel2' unless defined?( Mongrel2 )


# A collection of constants that are shared across the library
module Mongrel2::Constants

	# The path to the default Sqlite configuration database
	DEFAULT_CONFIG_URI = 'config.sqlite'

	# The default URI of the control socket
	DEFAULT_CONTROL_SOCKET = 'ipc://run/control'

	# Maximum number of identifiers that can be included in a broadcast response
	MAX_BROADCAST_IDENTS = 100


	# HTTP status and result constants
	module HTTP
		CONTINUE                      = 100
		SWITCHING_PROTOCOLS           = 101
		PROCESSING                    = 102

		OK                            = 200
		CREATED                       = 201
		ACCEPTED                      = 202
		NON_AUTHORITATIVE             = 203
		NO_CONTENT                    = 204
		RESET_CONTENT                 = 205
		PARTIAL_CONTENT               = 206
		MULTI_STATUS                  = 207

		MULTIPLE_CHOICES              = 300
		MOVED_PERMANENTLY             = 301
		MOVED                         = 301
		MOVED_TEMPORARILY             = 302
		REDIRECT                      = 302
		SEE_OTHER                     = 303
		NOT_MODIFIED                  = 304
		USE_PROXY                     = 305
		TEMPORARY_REDIRECT            = 307

		BAD_REQUEST                   = 400
		AUTH_REQUIRED                 = 401
		UNAUTHORIZED                  = 401
		PAYMENT_REQUIRED              = 402
		FORBIDDEN                     = 403
		NOT_FOUND                     = 404
		METHOD_NOT_ALLOWED            = 405
		NOT_ACCEPTABLE                = 406
		PROXY_AUTHENTICATION_REQUIRED = 407
		REQUEST_TIME_OUT              = 408
		CONFLICT                      = 409
		GONE                          = 410
		LENGTH_REQUIRED               = 411
		PRECONDITION_FAILED           = 412
		REQUEST_ENTITY_TOO_LARGE      = 413
		REQUEST_URI_TOO_LARGE         = 414
		UNSUPPORTED_MEDIA_TYPE        = 415
		RANGE_NOT_SATISFIABLE         = 416
		EXPECTATION_FAILED            = 417
		UNPROCESSABLE_ENTITY          = 422
		LOCKED                        = 423
		FAILED_DEPENDENCY             = 424
		UPGRADE_REQUIRED              = 426
		RECONDITION_REQUIRED          = 428
		TOO_MANY_REQUESTS             = 429
		REQUEST_HEADERS_TOO_LARGE     = 431

		SERVER_ERROR                  = 500
		NOT_IMPLEMENTED               = 501
		BAD_GATEWAY                   = 502
		SERVICE_UNAVAILABLE           = 503
		GATEWAY_TIME_OUT              = 504
		VERSION_NOT_SUPPORTED         = 505
		VARIANT_ALSO_VARIES           = 506
		INSUFFICIENT_STORAGE          = 507
		NOT_EXTENDED                  = 510

		# Stolen from Apache 2.2.6's modules/http/http_protocol.c
		STATUS_NAME = {
		    100 => "Continue",
		    101 => "Switching Protocols",
		    102 => "Processing",
		    200 => "OK",
		    201 => "Created",
		    202 => "Accepted",
		    203 => "Non-Authoritative Information",
		    204 => "No Content",
		    205 => "Reset Content",
		    206 => "Partial Content",
		    207 => "Multi-Status",
		    300 => "Multiple Choices",
		    301 => "Moved Permanently",
		    302 => "Found",
		    303 => "See Other",
		    304 => "Not Modified",
		    305 => "Use Proxy",
		    306 => "Undefined HTTP Status",
		    307 => "Temporary Redirect",
		    400 => "Bad Request",
		    401 => "Authorization Required",
		    402 => "Payment Required",
		    403 => "Forbidden",
		    404 => "Not Found",
		    405 => "Method Not Allowed",
		    406 => "Not Acceptable",
		    407 => "Proxy Authentication Required",
		    408 => "Request Time-out",
		    409 => "Conflict",
		    410 => "Gone",
		    411 => "Length Required",
		    412 => "Precondition Failed",
		    413 => "Request Entity Too Large",
		    414 => "Request-URI Too Large",
		    415 => "Unsupported Media Type",
		    416 => "Requested Range Not Satisfiable",
		    417 => "Expectation Failed",
		    418 => "Undefined HTTP Status",
		    419 => "Undefined HTTP Status",
		    420 => "Undefined HTTP Status",
		    421 => "Undefined HTTP Status",
		    406 => "Not Acceptable",
		    407 => "Proxy Authentication Required",
		    408 => "Request Time-out",
		    409 => "Conflict",
		    410 => "Gone",
		    411 => "Length Required",
		    412 => "Precondition Failed",
		    413 => "Request Entity Too Large",
		    414 => "Request-URI Too Large",
		    415 => "Unsupported Media Type",
		    416 => "Requested Range Not Satisfiable",
		    417 => "Expectation Failed",
		    418 => "Undefined HTTP Status",
		    419 => "Undefined HTTP Status",
		    420 => "Undefined HTTP Status",
		    421 => "Undefined HTTP Status",
		    422 => "Unprocessable Entity",
		    423 => "Locked",
		    424 => "Failed Dependency",
		    425 => "No code",
		    426 => "Upgrade Required",
		    428 => "Precondition Required",
		    429 => "Too Many Requests",
		    431 => "Request Headers too Large",
		    500 => "Internal Server Error",
		    501 => "Method Not Implemented",
		    502 => "Bad Gateway",
		    503 => "Service Temporarily Unavailable",
		    504 => "Gateway Time-out",
		    505 => "HTTP Version Not Supported",
		    506 => "Variant Also Negotiates",
		    507 => "Insufficient Storage",
		    508 => "Undefined HTTP Status",
		    509 => "Undefined HTTP Status",
		    510 => "Not Extended"
		}

		# A registry of HTTP status codes that don't allow an entity body
		# in the response.
		BODILESS_HTTP_RESPONSE_CODES = [
			CONTINUE,
			SWITCHING_PROTOCOLS,
			PROCESSING,
			NO_CONTENT,
			RESET_CONTENT,
			NOT_MODIFIED,
			USE_PROXY,
		]

	end


end # module Mongrel2::Constants

