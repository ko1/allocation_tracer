# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'allocation_tracer/version'

Gem::Specification.new do |spec|
  spec.name          = "allocation_tracer"
  spec.version       = ObjectSpace::AllocationTracer::VERSION
  spec.authors       = ["Koichi Sasada"]
  spec.email         = ["ko1@atdot.net"]
  spec.summary       = %q{allocation_tracer gem adds ObjectSpace::AllocationTracer module.}
  spec.description   = %q{allocation_tracer gem adds ObjectSpace::AllocationTracer module.}
  spec.homepage      = "https://github.com/ko1/allocation_tracer"
  spec.license       = "MIT"

  spec.extensions    = %w[ext/allocation_tracer/extconf.rb]
  spec.required_ruby_version = '>= 2.1.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
  spec.add_development_dependency "rspec"
end
