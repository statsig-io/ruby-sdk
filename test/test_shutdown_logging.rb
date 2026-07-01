require_relative 'test_helper'
require 'minitest'
require 'minitest/autorun'
require 'statsig'

class ShutdownLoggingTest < BaseTest
  suite :ShutdownLoggingTest

  # local_mode keeps the driver offline + deterministic (mirrors the customer repro).
  def new_local_driver
    StatsigDriver.new(SDK_KEY, StatsigOptions.new(local_mode: true))
  end

  # A fresh user per call avoids the per-user verify_inputs memo, so each call genuinely
  # reaches check_shutdown — the path that used to print once per evaluation.
  def test_shutdown_notice_emitted_once_across_eval_and_log_paths
    driver = new_local_driver
    driver.shutdown

    out, _err = capture_io do
      3.times { driver.check_gate(StatsigUser.new(user_id: 'u123'), 'any_gate') }
      driver.log_event(StatsigUser.new(user_id: 'u123'), 'any_event')
    end

    assert_equal(1, out.scan('SDK has been shutdown.').length,
                 'expected the shutdown notice exactly once across many post-shutdown calls')
    assert_includes(out, '[Statsig]: SDK has been shutdown.',
                    'expected the shutdown notice to carry the [Statsig]: prefix')
  end

  def test_no_shutdown_notice_before_shutdown
    driver = new_local_driver

    out, _err = capture_io do
      3.times { driver.check_gate(StatsigUser.new(user_id: 'u123'), 'any_gate') }
    end

    refute_includes(out, 'SDK has been shutdown.',
                    'expected no shutdown notice before shutdown')
  end
end
