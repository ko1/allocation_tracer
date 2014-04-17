require "bundler/gem_tasks"
require "rake/extensiontask"
require 'rspec/core/rake_task'

spec = Gem::Specification.load('allocation_tracer.gemspec')

Rake::ExtensionTask.new("allocation_tracer", spec){|ext|
  ext.lib_dir = "lib/allocation_tracer"
}

RSpec::Core::RakeTask.new('spec' => 'compile')

task default: :spec

task :run => 'compile' do
  ruby %q{-I ./lib test.rb}
end
