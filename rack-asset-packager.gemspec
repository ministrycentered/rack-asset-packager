# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{rack-asset-packager}
  s.version = "0.1.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Jeff Berg"]
  s.email = %q{jeff@ministrycentered.com}
  s.files = ["lib/rack/asset-packager.rb", "rack-asset-packager.gemspec"]
  s.homepage = %q{http://github.com/ministrycentered/rack-asset-packager}
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{rack-asset-packager}
  s.rubygems_version = %q{1.3.6}
  s.summary = %q{bundles assets dynamically}
  
  s.add_dependency 'yui-compressor'
  s.add_dependency 'closure-compiler'
end
