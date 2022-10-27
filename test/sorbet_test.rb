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

  sig {override.params(x: Integer).void}

  def bad_sig_validation_method(x)
    # Bad because it is marked as override, but has no parent class
  end
end

# All these tests would throw if not for the requiring of
# statsig which has custom handlers for each of these
class SorbetTest < Minitest::Test

  def test_inline_type_error_handler
    assert_output(/T.assert_type!: Expected type String, got type Integer with value 1/) do
      T.assert_type!(1, String)
    end
  end

  def test_call_validation_error_handler
    assert_output(/Parameter 'error_callback': Expected type T.nilable\(T.any\(Method, Proc\)\), got type Integer with value 1/) do
      Statsig.initialize('secret-key', StatsigOptions.new(local_mode: true), 1)
    end
  end

  def test_sig_builder_error_handler
    assert_output(/Return value: Expected type String, got type NilClass/) do
      BadClass.new.bad_sig_builder_method
    end
  end

  def test_sig_validation_error_handler
    assert_output(/You marked `bad_sig_validation_method` as .override, but that method doesn't already exist in this class/) do
      BadClass.new.bad_sig_validation_method(1)
    end
  end

end