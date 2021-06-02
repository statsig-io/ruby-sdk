Gem::Specification.new do |s|
    s.name        = 'statsig'
    s.version     = '0.1.2'
    s.summary     = 'Statsig server SDK for Ruby'
    s.description = 'Statsig server SDK for feature gates and experimentation in Ruby'
    s.authors     = ['Statsig, Inc']
    s.email       = 'support@statsig.com'
    s.homepage    = 'https://rubygems.org/gems/statsig'
    s.license       = 'ISC'
    s.files       = Dir['lib/**/*']
    s.add_development_dependency "bundler", "~> 2.1"
    s.add_runtime_dependency 'browser', '~>5.3', '>= 5.3.1'
    s.add_runtime_dependency 'http', '~>4.4', '>= 4.4.1'
  end
