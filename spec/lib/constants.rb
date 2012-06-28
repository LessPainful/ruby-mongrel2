#!/usr/bin/env ruby

require 'uri'
require 'yajl'
require 'tnetstring'

require 'mongrel2' unless defined?( Mongrel2 )


### A collection of constants used in testing
module Mongrel2::TestConstants # :nodoc:all

	include Mongrel2::Constants,
	        Mongrel2::WebSocket::Constants

	unless defined?( TEST_HOST )

		TEST_HOST = 'localhost'
		TEST_PORT = 8118

		# Rule 2: Every message to and from Mongrel2 has that Mongrel2 instances
		#   UUID as the very first thing.
		TEST_UUID = 'BD17D85C-4730-4BF2-999D-9D2B2E0FCCF9'

		# 0mq socket specifications for Handlers
		TEST_SEND_SPEC = 'tcp://127.0.0.1:9998'
		TEST_RECV_SPEC = 'tcp://127.0.0.1:9997'

		# Rule 3: Mongrel2 sends requests with one number right after the
		#   servers UUID separated by a space. Handlers return a netstring with
		#   a list of numbers separated by spaces. The numbers indicate the
		#   connected browser the message is to/from.
		TEST_ID = 8

		#
		# HTTP request constants
		#

		TEST_ROUTE = '/handler'
		TEST_PATH  = TEST_ROUTE
		TEST_QUERY = 'thing=foom'

		TEST_HEADERS = {
			"x-forwarded-for" => "127.0.0.1",
			"accept-language" => "en-US,en;q=0.8",
			"accept-encoding" => "gzip,deflate,sdch",
			"connection"      => "keep-alive",
			"accept-charset"  => "UTF-8,*;q=0.5",
			"accept"          => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
			"user-agent"      => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_7_1) " +
			                     "AppleWebKit/535.1 (KHTML, like Gecko) Chrome/13.0.782.112 " +
			                     "Safari/535.1",
			"host"            => "localhost:3667",
			"METHOD"          => "GET",
			"VERSION"         => "HTTP/1.1",
		}

		TEST_BODY = ''

		TEST_REQUEST_OPTS = {
			:uuid    => TEST_UUID,
			:id      => TEST_ID,
			:path    => TEST_PATH,
			:body    => TEST_BODY,
		}


		#
		# JSON (JSSocket, etc.) request constants
		#

		TEST_JSON_PATH = '@directory'

		TEST_JSON_HEADERS = {
			'PATH'            => TEST_JSON_PATH,
			'x-forwarded-for' => "127.0.0.1",
			'METHOD'          => "JSON",
			'PATTERN'         => TEST_JSON_PATH,
		}
		TEST_JSON_BODY = { 'type' => 'msg', 'msg' => 'connect' }

		TEST_JSON_REQUEST_OPTS = {
			:uuid    => TEST_UUID,
			:id      => TEST_ID,
			:path    => TEST_JSON_PATH,
			:body    => TEST_JSON_BODY,
		}


		#
		# XML message request constants
		#

		TEST_XML_PATH = '<directory'

		TEST_XML_HEADERS = {
			'PATH'            => TEST_XML_PATH,
			'x-forwarded-for' => "127.0.0.1",
			'METHOD'          => "XML",
			'PATTERN'         => TEST_XML_PATH,
		}
		TEST_XML_BODY = '<directory><file name="foom.txt" /><file name="foom2.md" /></directory>'

		TEST_XML_REQUEST_OPTS = {
			:uuid    => TEST_UUID,
			:id      => TEST_ID,
			:path    => TEST_XML_PATH,
			:body    => TEST_XML_BODY,
		}


		#
		# WebSocket frame constants
		#

		TEST_WEBSOCKET_PATH = '/ws'

		TEST_WEBSOCKET_HEADERS = {
			 'connection'               => 'Upgrade',
			 'FLAGS'                    => '0x8A',
			 'host'                     => 'host.example.com:80',
			 'METHOD'                   => 'WEBSOCKET',
			 'origin'                   => 'http://host.example.com:80',
			 'PATH'                     => TEST_WEBSOCKET_PATH,
			 'PATTERN'                  => TEST_WEBSOCKET_PATH,
			 'sec-websocket-extensions' => 'x-webkit-deflate-frame',
			 'sec-websocket-key'        => 'SQvDVdT2SbgTg6P/lSZo7Q==',
			 'sec-websocket-protocol'   => 'echo',
			 'sec-websocket-version'    => '13',
			 'upgrade'                  => 'websocket',
			 'URI'                      => TEST_WEBSOCKET_PATH,
			 'VERSION'                  => 'HTTP/1.1',
			 'x-forwarded-for'          => '127.0.0.2',
		}
		TEST_WEBSOCKET_HANDSHAKE_HEADERS = {
			'connection'               => 'Upgrade',
			'host'                     => 'host.example.com:80',
			'METHOD'                   => 'WEBSOCKET_HANDSHAKE',
			'origin'                   => 'http://host.example.com:80',
			'PATH'                     => TEST_WEBSOCKET_PATH,
			'PATTERN'                  => TEST_WEBSOCKET_PATH,
			'sec-websocket-extensions' => 'x-webkit-deflate-frame',
			'sec-websocket-key'        => 'SQvDVdT2SbgTg6P/lSZo7Q==',
			'sec-websocket-protocol'   => 'echo',
			'sec-websocket-version'    => '13',
			'upgrade'                  => 'websocket',
			'URI'                      => TEST_WEBSOCKET_PATH,
			'VERSION'                  => 'HTTP/1.1',
			'x-forwarded-for'          => '127.0.0.2',
		}
		TEST_WEBSOCKET_BODY = 'GR7M5bFPiY2GvVc5a7CIMErQ18Q='
		TEST_WEBSOCKET_REQUEST_OPTS = {
			:uuid    => TEST_UUID,
			:id      => TEST_ID,
			:path    => TEST_WEBSOCKET_PATH,
			:body    => '',
		}


		#
		# HTTP constants
		#

		# Space
		SP = '\\x20'

		# Network EOL
		CRLF = '\\r\\n'

		# Pattern to match the contents of ETag and If-None-Match headers
		ENTITY_TAG_PATTERN = %r{
			(w/)?       # Weak flag
			"           # Opaque-tag
				([^"]+) # Quoted-string
			"           # Closing quote
		  }ix

		# Separators    = "(" | ")" | "<" | ">" | "@"
		#                  | "," | ";" | ":" | "\" | <">
		#                  | "/" | "[" | "]" | "?" | "="
		#                  | "{" | "}" | SP | HT
		SEPARATORS = Regexp.quote("(\")<>@,;:\\/[]?={} \t")

		# token         = 1*<any CHAR except CTLs or separators>
		TOKEN = /[^#{SEPARATORS}[:cntrl:]]+/

		# Borrow URI's pattern for matching absolute URIs
		REQUEST_URI = URI::REL_URI_REF

		# Canonical HTTP methods
		REQUEST_METHOD = /OPTIONS|GET|HEAD|POST|PUT|DELETE|TRACE|CONNECT/

		# Extension HTTP methods
		# extension-method = token
		EXTENSION_METHOD = TOKEN

		# HTTP-Version   = "HTTP" "/" 1*DIGIT "." 1*DIGIT
		HTTP_VERSION = %r{HTTP/(\d+\.\d+)}

		# LWS            = [CRLF] 1*( SP | HT )
		LWS = /#{CRLF}[ \t]+/

		# TEX            = <any OCTET except CTLs, but including LWS>
		TEXT = /[^[:cntrl:]]|#{LWS}/

		# Reason-Phrase  = *<TEXT, excluding CR, LF>
		REASON_PHRASE = %r{[^[:cntrl:]]+}

		# Pattern to match HTTP response lines
		#	Status-Line = HTTP-Version SP Status-Code SP Reason-Phrase CRLF
		HTTP_RESPONSE_LINE = %r{
			(?<http_version>#{HTTP_VERSION})
			#{SP}
			(?<status_code>\d{3})
			#{SP}
			(?<reason_phrase>#{REASON_PHRASE})
			#{CRLF}
		}x

		# message-header = field-name ":" [ field-value ]
		# field-name     = token
		# field-value    = *( field-content | LWS )
		# field-content  = <the OCTETs making up the field-value
		#                  and consisting of either *TEXT or combinations
		#                  of token, separators, and quoted-string>

		# Pattern to match a single header tuple, possibly split over multiple lines
		HEADER_LINE = %r{
			^
			#{TOKEN}
			:
			(?:#{LWS}|#{TEXT})*
			#{CRLF}
		}mx

		# entity-body	 = *OCTET
		MESSAGE_BODY = /.*/

		# Pattern to match an entire HTTP response
		#   Response      = Status-Line               ; Section 6.1
		#                   *(( general-header        ; Section 4.5
		#                    | response-header        ; Section 6.2
		#                    | entity-header ) CRLF)  ; Section 7.1
		#                   CRLF
		#                   [ message-body ]          ; Section 7.2
		HTTP_RESPONSE = %r{
			^
			(?<response_line>#{HTTP_RESPONSE_LINE})
			(?<headers>#{HEADER_LINE}*)
			#{CRLF}
			(?<message_body>#{MESSAGE_BODY})
		}x

		# wkday        = "Mon" | "Tue" | "Wed"
		#              | "Thu" | "Fri" | "Sat" | "Sun"
		WKDAY =	 Regexp.union( %w[Mon Tue Wed Thu Fri Sat Sun] )

		# month        = "Jan" | "Feb" | "Mar" | "Apr"
		#              | "May" | "Jun" | "Jul" | "Aug"
		#              | "Sep" | "Oct" | "Nov" | "Dec"
		MONTH = Regexp.union( %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec] ) 

		# Match an RFC1123 "HTTP date"
		# rfc1123-date = wkday "," SP date1 SP time SP "GMT"
		# date1        = 2DIGIT SP month SP 4DIGIT
		#                ; day month year (e.g., 02 Jun 1982)
		# time         = 2DIGIT ":" 2DIGIT ":" 2DIGIT
		#                ; 00:00:00 - 23:59:59
		HTTP_DATE = %r{
			#{WKDAY} , #{SP}
			\d{2} #{SP}
			#{MONTH} #{SP}
			\d{4} #{SP}
			\d{2} : \d{2} : \d{2} #{SP} GMT
		}x


		# Freeze all testing constants
		constants.each do |cname|
			const_get(cname).freeze
		end
	end

end


