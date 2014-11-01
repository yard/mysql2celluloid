# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mysql2celluloid/version'

Gem::Specification.new do |spec|
  spec.name          = "mysql2celluloid"
  spec.version       = Mysql2celluloid::VERSION
  spec.authors       = ["Anton Zhuravsky"]
  spec.email         = ["mail2lf@gmail.com"]
  spec.summary       = %q{FiberConnnectionPool-driven Celluloid + Celluloid IO enabled Mysql2 backed connection adapter}
  spec.description   = %q{Just replace your adapter with mysql2celluloid in your database.yml file and your are good to go}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord"
  spec.add_dependency "mysql2"
  spec.add_dependency "fiber_connection_pool"
  spec.add_dependency "celluloid-io", "= 0.15.0"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
end
