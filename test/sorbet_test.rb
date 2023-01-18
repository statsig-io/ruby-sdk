#typed: ignore

require 'minitest'
require 'minitest/autorun'
require 'webmock/minitest'
require 'sorbet-runtime'

require 'statsig'

class BadClass
  extend T::Sig

  sig { returns(String) }

  def bad_sig_builder_method
    # Bad because it does not return a string
  end

  sig { override.params(x: Integer).void }

  def bad_sig_validation_method(x)
    # Bad because it is marked as override, but has no parent class
  end

  sig { override.params(x: Integer).void }

  def bad_sig_validation_method_two(x)
    # Bad because it is marked as override, but has no parent class
  end

  sig { override.params(x: Integer).void }

  def bad_sig_validation_method_three(x)
    # Bad because it is marked as override, but has no parent class
  end
end

# All these tests would throw if not for the requiring of
# statsig which has custom handlers for each of these
class SorbetTest < Minitest::Test

  def setup
    reset_for_test
  end

  def teardown
    reset_for_test
  end

  # Test inline_type_error_handler

  def test_inline_type_error_handler_throws_when_statsig_is_not_initialized
    assert_raises TypeError do
      T.assert_type!(1, String)
    end
  end

  def test_inline_type_error_handler_throws_when_logging_is_disabled
    opts = StatsigOptions::new(local_mode: true, disable_sorbet_logging_handlers: true)
    Statsig.initialize("secret-key", opts)

    assert_raises TypeError do
      T.assert_type!(1, String)
    end
  end

  def test_inline_type_error_handler_logs_to_console
    Statsig.initialize("secret-key", StatsigOptions::new(local_mode: true))

    assert_output(/T.assert_type!: Expected type String, got type Integer with value 1/) do
      T.assert_type!(1, String)
    end
  end

  # Test call_validation_error_handler

  def test_call_validation_error_handler_throws_when_statsig_is_not_initialized
    assert_raises TypeError do
      Statsig.initialize('secret-key', StatsigOptions.new(local_mode: true), 1)
    end
  end

  def test_call_validation_error_handler_throws_when_logging_is_disabled
    opts = StatsigOptions::new(local_mode: true, disable_sorbet_logging_handlers: true)
    Statsig.initialize("secret-key", opts)

    assert_raises TypeError do
      Statsig.initialize('secret-key', StatsigOptions.new(local_mode: true), 1)
    end
  end

  def test_call_validation_error_handler_logs_to_console
    Statsig.initialize("secret-key", StatsigOptions::new(local_mode: true))

    assert_output(/Parameter 'error_callback': Expected type T.nilable\(T.any\(Method, Proc\)\), got type Integer with value 1/) do
      Statsig.initialize('secret-key', StatsigOptions.new(local_mode: true), 1)
    end
  end

  # Test sig_builder_error_handler

  def test_sig_builder_error_handler_throws_when_statsig_is_not_initialized
    assert_raises TypeError do
      BadClass.new.bad_sig_builder_method
    end
  end

  def test_sig_builder_error_handler_throws_when_logging_is_disabled
    opts = StatsigOptions::new(local_mode: true, disable_sorbet_logging_handlers: true)
    Statsig.initialize("secret-key", opts)

    assert_raises TypeError do
      BadClass.new.bad_sig_builder_method
    end
  end

  def test_sig_builder_error_handler_logs_to_console
    Statsig.initialize("secret-key", StatsigOptions::new(local_mode: true))

    assert_output(/Return value: Expected type String, got type NilClass/) do
      BadClass.new.bad_sig_builder_method
    end
  end

  # Test sig_validation_error_handler

  def test_sig_validation_error_handler_throws_when_statsig_is_not_initialized
    called = false
    begin
      BadClass.new.bad_sig_validation_method(1)
    rescue
      called = true
    end

    assert_equal(true, called)
  end

  def test_sig_validation_error_handler_throws_when_logging_is_disabled
    opts = StatsigOptions::new(local_mode: true, disable_sorbet_logging_handlers: true)
    Statsig.initialize("secret-key", opts)

    called = false
    begin
      BadClass.new.bad_sig_validation_method_two(1)
    rescue
      called = true
    end

    assert_equal(true, called)

  end

  def test_sig_validation_error_handler_logs_to_console
    Statsig.initialize("secret-key", StatsigOptions::new(local_mode: true))

    assert_output(/You marked `bad_sig_validation_method_three` as .override, but that method doesn't already exist in this class/) do
      BadClass.new.bad_sig_validation_method_three(1)
    end
  end

  private

  def reset_for_test
    Statsig.shutdown

    T::Configuration.call_validation_error_handler = nil
    T::Configuration.inline_type_error_handler = nil
    T::Configuration.sig_builder_error_handler = nil
    T::Configuration.sig_validation_error_handler = nil
  end

end