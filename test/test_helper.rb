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

module Spy
  class Subroutine
    def returned?(result = nil)
      has_been_called? && !calls.find { |e| result.nil? ? !e.result.nil? : e.result == result }.nil?
    end

    def finished?
      returned?('mark_spied_method_finished')
    end

    # Calls through the original method but replaces the return value with a marker
    # that can be checked for when the method finishes
    def and_call_through_void
      and_return do |*args|
        base_object.send("original_#{method_name}", *args)
        'mark_spied_method_finished'
      end
    end
  end

  class << self
    alias parent_on on
    def on(base_object, *method_names)
      save_original_methods(base_object, *method_names)
      parent_on(base_object, *method_names)
    end

    def save_original_methods(base_object, *methods)
      method_names = methods
      if methods.empty?
        method_names = base_object.methods
      end
      method_names.each do |name|
        base_object.singleton_class.send(:alias_method, "original_#{name}", name)
      end
    end
  end
end
