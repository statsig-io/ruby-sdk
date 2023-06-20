# typed: ignore

require 'simplecov'
require 'simplecov-lcov'
require 'simplecov-cobertura'
SimpleCov.formatter = if ENV['COVERAGE_FORMAT'] == 'cobertura'
                        SimpleCov::Formatter::CoberturaFormatter
                      elsif ENV['COVERAGE_FORMAT'] == 'lcov'
                        SimpleCov::Formatter::LcovFormatter
                      else
                        SimpleCov::Formatter::HTMLFormatter
                      end
SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
SimpleCov.start { add_filter '/test/' } if ENV['COVERAGE']

require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'spy'
require 'statsig'

module Minitest::Assertions
  def assert_nothing_raised(*)
    yield
  end
end

def wait_for(timeout: 10)
  start = Time.now
  x = yield
  until x
    if Time.now - start > timeout
      raise "Waited too long here. Timeout #{timeout} sec"
    end

    sleep(0.1)
    x = yield
  end
end
