#!/usr/bin/env rake

begin
	require 'hoe'
rescue LoadError
	abort "This Rakefile requires 'hoe' (gem install hoe)"
end

# Work around borked RSpec support in this version
if Hoe::VERSION == '2.12.0'
	warn "Ignore warnings about not having rspec; it's a bug in Hoe 2.12.0"
	require 'rspec'
end

Hoe.plugin :mercurial
Hoe.plugin :signing
Hoe.plugin :deveiate

Hoe.plugins.delete :rubyforge

hoespec = Hoe.spec 'mongrel2' do
	self.readme_file = 'README.rdoc'
	self.history_file = 'History.rdoc'
	self.extra_rdoc_files = Rake::FileList[ '*.rdoc' ]

	self.developer 'Michael Granger', 'ged@FaerieMUD.org'

	self.dependency 'nokogiri',   '~> 1.5'
	self.dependency 'sequel',     '~> 3.34'
	self.dependency 'tnetstring', '~> 0.3'
	self.dependency 'yajl-ruby',  '~> 1.0'
	self.dependency 'trollop',    '~> 1.16'
	self.dependency 'sysexits',   '~> 1.0'
	self.dependency 'zmq',        '~> 2.1'
	self.dependency 'loggability','~> 0.2'

	self.dependency 'configurability', '~> 1.0', :developer
	self.dependency 'simplecov',       '~> 0.6', :developer
	self.dependency 'hoe-deveiate',    '~> 0.1', :developer

	self.spec_extras[:licenses] = ["BSD"]
	self.spec_extras[:rdoc_options] = ['-f', 'fivefish', '-t', 'Mongrel2 Ruby Connector']
	self.require_ruby_version( '>= 1.9.2' )

	self.hg_sign_tags = true if self.respond_to?( :hg_sign_tags= )
	self.check_history_on_release = true if self.respond_to?( :check_history_on_release= )

	self.rdoc_locations << "deveiate:/usr/local/www/public/code/#{remote_rdoc_dir}"
end

ENV['VERSION'] ||= hoespec.spec.version.to_s

# Ensure the specs pass before checking in
task 'hg:precheckin' => [:check_manifest, :check_history, :spec]

# Rebuild the ChangeLog immediately before release
task :prerelease => [:check_manifest, :check_history, 'ChangeLog']

task :check_manifest => 'ChangeLog'


desc "Build a coverage report"
task :coverage do
	ENV["COVERAGE"] = 'yes'
	Rake::Task[:spec].invoke
end

