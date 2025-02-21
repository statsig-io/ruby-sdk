require 'minitest/autorun'
require 'concurrent-ruby'
require 'statsig'

class TestSDKConfigs < Minitest::Test
  def setup
    @sdk_configs = Statsig::SDKConfigs.new
  end

  def test_set_and_get_configs
    @sdk_configs.set_configs({ "timeout" => 30, "threshold" => 0.5 })
    assert_equal 30, @sdk_configs.get_config_num_value("timeout")
    assert_equal 0.5, @sdk_configs.get_config_num_value("threshold")
    assert_nil @sdk_configs.get_config_num_value("non_existent")
  end

  def test_set_flags
    @sdk_configs.set_flags({ "feature_x" => true, "feature_y" => false })
    assert_equal true, @sdk_configs.on("feature_x")
    assert_equal false, @sdk_configs.on("feature_y")
  end

  def test_invalid_config_type
    @sdk_configs.set_configs({ "name" => "example" })
    assert_nil @sdk_configs.get_config_num_value("name")
  end

  def test_empty_configs
    @sdk_configs.set_configs({})
    assert_nil @sdk_configs.get_config_num_value("timeout")
  end

  def test_nil_configs
    @sdk_configs.set_configs(nil)
    assert_nil @sdk_configs.get_config_num_value("timeout")
  end
end