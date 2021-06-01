Gem::Specification.new do |s|
    s.name        = 'statsig'
    s.version     = '0.0.0'
    s.summary     = 'Statsig server SDK for Ruby'
    s.description = 'Statsig server SDK for feature gates and experimentation in Ruby'
    s.authors     = ['Statsig, Inc']
    s.email       = 'support@statsig.com'
    s.homepage    = 'https://rubygems.org/gems/statsig'
    s.license       = 'ISC'
    s.files       = Dir['lib/**/*']
    s.add_development_dependency 'concurrent-ruby', '~>1.1', '>= 1.1.0'
    s.add_development_dependency 'http', '~>4.4', '>= 4.4.1'
    s.add_development_dependency 'browser', '~>5.3', '>= 5.3.1'
    s.add_runtime_dependency 'browser', '~>5.3', '>= 5.3.1'
    s.add_runtime_dependency 'concurrent-ruby', '~>1.1', '>= 1.1.0'
    s.add_runtime_dependency 'http', '~>4.4', '>= 4.4.1'
  end