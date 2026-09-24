# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)
require "saml2/version"

Gem::Specification.new do |s|
  s.name = "ruby-saml2-sans"
  s.version = SAML2::VERSION
  s.platform = Gem::Platform::RUBY
  s.authors = ["Cody Cutrer", "Onetime Secret"]
  s.homepage = "https://github.com/onetimesecret/ruby-saml2-sans"
  s.summary = "SAML 2.0 Library (fork of saml2 without ActiveSupport)"
  s.description = <<~TEXT
    A fork of Instructure's saml2 gem with no ActiveSupport dependency.
    It keeps the saml2 require path and SAML2 namespace, so it cannot be
    installed alongside the upstream saml2 gem.

    The saml2 library is yet another SAML library for Ruby, with
    an emphasis on _not_ re-implementing XML, especially XML Security,
    _not_ parsing via Regex or generating XML by string concatenation,
    _not_ serializing/re-parsing multiple times just to get it into
    the correct format to sign or validate.
  TEXT
  s.license = "MIT"
  s.bindir = "exe"
  s.executables = "bulk_verify_responses"
  s.files = Dir["{app,lib,schemas,exe}/**/*"] + ["Rakefile"]

  s.required_ruby_version = ">= 3.2"

  # Very specifically at least 1.5.8 - they fixed a bug with namespaces
  # on root elements with XML::Builder in that release
  s.add_dependency "nokogiri", ">= 1.5.8", "< 2.0"
  s.add_dependency "nokogiri-xmlsec-instructure", "~> 0.9", ">= 0.9.5"

  s.metadata["source_code_uri"] = "#{s.homepage}/tree/main"
  s.metadata["bug_tracker_uri"] = "#{s.homepage}/issues"
  s.metadata["rubygems_mfa_required"] = "true"
end
