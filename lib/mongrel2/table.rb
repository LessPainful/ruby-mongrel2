#!/usr/bin/ruby

require 'forwardable'
require 'loggability'

require 'mongrel2' unless defined?( Mongrel2 )


# The Mongrel2 Table class. Instances of this class provide a case-insensitive hash-like
# object that can store multiple values per key.
#
#   headers = Mongrel2::Table.new
#   headers['User-Agent'] = 'PornBrowser 1.1.5'
#   headers['user-agent']  # => 'PornBrowser 1.1.5'
#   headers[:user_agent]   # => 'PornBrowser 1.1.5'
#   headers.user_agent     # => 'PornBrowser 1.1.5'
#
# == Author/s
#
# * Michael Granger <ged@FaerieMUD.org>
# * Mahlon E. Smith <mahlon@martini.nu>
#
class Mongrel2::Table
	extend Forwardable,
	       Loggability

	# Loggability API -- set up logging under the 'mongrel2' log host
	log_to :mongrel2

	# Methods that understand case-insensitive keys
	KEYED_METHODS = [ :"[]", :"[]=", :delete, :fetch, :has_key?, :include?, :member?, :store ]


	### Auto-generate methods which call the given +delegate+ after normalizing
	### their first argument via +normalize_key+
	def self::def_normalized_delegators( delegate, *syms )
		syms.each do |methodname|
			define_method( methodname ) do |key, *args|
				nkey = normalize_key( key )
				instance_variable_get( delegate ).
					__send__( methodname, nkey, *args )
			end
		end
	end


	#################################################################
	###	I N S T A N C E   M E T H O D S
	#################################################################

	### Create a new Mongrel2::Table using the given +hash+ for initial
	### values.
	def initialize( initial_values={} )
		@hash = {}
		initial_values.each {|k,v| self.append(k => v) }
	end


	### Make sure the inner Hash is unique on duplications.
	def initialize_copy( * ) # :nodoc:
		@hash = deep_copy( @hash )
	end


	######
	public
	######

	# Delegate a handful of methods to the underlying Hash after normalizing
	# the key.
	def_normalized_delegators :@hash, *KEYED_METHODS


	# Delegate some methods to the underlying Hash
	begin
		unoverridden_methods = Hash.instance_methods(false).collect {|mname| mname.to_sym }
		def_delegators :@hash, *( unoverridden_methods - KEYED_METHODS )
	end


	### Append the keys and values in the given +hash+ to the table, transforming
	### each value into an array if there was an existing value for the same key.
	def append( hash )
		self.merge!( hash ) do |key,origval,newval|
			[ origval, newval ].flatten
		end
	end


	### Return the Table as RFC822 headers in a String
	def to_s
		@hash.collect do |header,value|
			Array( value ).collect {|val|
				"%s: %s" % [
					normalize_header( header ),
					val
				]
			}
		end.flatten.sort.join( "\r\n" ) + "\r\n"
	end


	### Enumerator for iterating over the table contents, yielding each as an RFC822 header.
	def each_header( &block )
		enum = Enumerator.new do |yielder|
			@hash.each do |header, value|
				Array( value ).each do |val|
					yielder.yield( normalize_header(header), val.to_s )
				end
			end
		end

		if block
			return enum.each( &block )
		else
			return enum
		end
	end


	### Return the Table as a hash.
	def to_h
		@hash.dup
	end
	alias_method :to_hash, :to_h


	### Merge +other_table+ into the receiver.
	def merge!( other_table, &merge_callback )
		nhash = normalize_hash( other_table.to_hash )
		@hash.merge!( nhash, &merge_callback )
	end
	alias_method :update!, :merge!


	### Return a new table which is the result of merging the receiver
	### with +other_table+ in the same fashion as Hash#merge. If the optional
	### +merge_callback+ block is provided, it is called whenever there is a
	### key collision between the two.
	def merge( other_table, &merge_callback ) # :yields: key, original_value, new_value
		other = self.dup
		other.merge!( other_table, &merge_callback )
		return other
	end
	alias_method :update, :merge


	### Return an array containing the values associated with the given
	### keys.
	def values_at( *keys )
		@hash.values_at( *(keys.collect {|k| normalize_key(k)}) )
	end


	#########
	protected
	#########

	### Proxy method: handle getting/setting headers via methods instead of the
	### index operator.
	def method_missing( sym, *args )
		# work magic
		return super unless sym.to_s =~ /^([a-z]\w+)(=)?$/

		# If it's an assignment, the (=)? will have matched
		key, assignment = $1, $2

		method_body = nil
		if assignment
			method_body = self.make_setter( key )
		else
			method_body = self.make_getter( key )
		end

		self.class.send( :define_method, sym, &method_body )
		return self.method( sym ).call( *args )
	end


	### Create a Proc that will act as a setter for the given key
	def make_setter( key )
		return Proc.new {|new_value| self[ key ] = new_value }
	end


	### Create a Proc that will act as a getter for the given key
	def make_getter( key )
		return Proc.new { self[key] }
	end


	#######
	private
	#######

	### Return a copy of +hash+ with all of its keys normalized by #normalize_key.
	def normalize_hash( hash )
		hash = hash.dup
		hash.keys.each do |key|
			nkey = normalize_key( key )
			hash[ nkey ] = hash.delete( key ) if key != nkey
		end

		return hash
	end


	### Normalize the given key to equivalence
	def normalize_key( key )
		key.to_s.downcase.gsub('-', '_').to_sym
	end


	### Return the given key as an RFC822-style header label
	def normalize_header( key )
		key.to_s.split( '_' ).collect {|part| part.capitalize }.join( '-' )
	end


	### Recursively copying the specified +obj+ and return the result.
	def deep_copy( obj )
		# Handle mocks during testing
		return obj if obj.class.name == 'RSpec::Mocks::Mock'

		return case obj
				when NilClass, Numeric, TrueClass, FalseClass, Symbol
						obj

				when Array
						obj.map {|o| deep_copy(o) }

				when Hash
						newhash = {}
						obj.each do |k,v|
								newhash[ deep_copy(k) ] = deep_copy( v )
						end
						newhash

				else
						obj.clone
				end
	end

end # class Mongrel2::Table

# vim: set nosta noet ts=4 sw=4:

