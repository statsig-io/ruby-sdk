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
require 'minitest/reporters'
require 'minitest/suite'
require 'webmock/minitest'
require 'spy'
require 'statsig'

# Minitest overrides & plugin settings
module Minitest::Assertions
  def assert_nothing_raised(*)
    yield
  rescue StandardError => e
    assert(false, "Failed asserting that nothing raised (#{e})")
  end
end

unless ENV['RM_INFO'] # For compatibility with IntelliJ Minitest
  Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
end

Minitest::Suite.order = %i[
  ClientInitializeResponseTest
  StatsigDataAdapterTest
  DynamicConfigTest
  EvaluationDetailsTest
  LayerExposureTest
  LayerTest
  StatsigLocalOverridesTest
  ManualExposureTest
  ServerSDKConsistencyTest
  SorbetTest
  StatsigE2ETest
  TestConcurrency
  CountryLookupTest
  InitDiagnosticsTest
  ErrorBoundaryTest
  EvaluateUserProvidedHashesTest
  TestLogging
  TestNetwork
  TestNetworkTimeout
  TestStatsig
  StatsigErrorBoundaryUsageTest
  TestStore
  TestSymbolHashes
  TestURIHelper
  UserFieldsTest
]

class BaseTest < Minitest::Test
  include Minitest::Assertions
  def self.test_order
    :alpha
  end

  def setup
    super
  end

  def teardown
    super
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
