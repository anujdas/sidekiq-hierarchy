# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sidekiq/hierarchy/version'

Gem::Specification.new do |spec|
  spec.name          = "sidekiq-hierarchy"
  spec.version       = Sidekiq::Hierarchy::VERSION
  spec.authors       = ["Anuj Das"]
  spec.email         = ["anujdas@gmail.com"]

  spec.summary       = %q{A set of sidekiq middlewares to track workflows consisting of multiple levels of sidekiq jobs}
  spec.description   = %q{A set of sidekiq middlewares to track workflows consisting of multiple levels of sidekiq jobs}
  spec.homepage      = 'https://www.github.com/anujdas/sidekiq-hierarchy'
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'sidekiq', '~> 3.3'

  spec.add_development_dependency 'bundler', '~> 1.10'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-its'
  spec.add_development_dependency 'fakeredis'
  spec.add_development_dependency 'rspec-sidekiq'

  spec.add_development_dependency 'faraday'
  spec.add_development_dependency 'rack'
end
