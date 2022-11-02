require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'

class StatsigErrorBoundaryUsageTest < Minitest::Test

  def before_setup
    super
    stub_request(:post, 'https://statsigapi.net/v1/sdk_exception').to_return(status: 200)
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 500)
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 500)
  end

  def setup
    WebMock.enable!
    @driver = StatsigDriver.new("secret-key")
    @user = StatsigUser.new({ "userID" => "dloomb" })

    @driver.instance_variable_set('@evaluator', 1)
    @driver.instance_variable_set('@logger', 1)
  end

  def teardown
    super
    WebMock.disable!
  end

  def test_errors_with_check_gate
    res = @driver.check_gate(@user, "a_gate")
    assert_equal(false, res)
    assert_exception("NoMethodError", "undefined method `check_gate'")
  end

  def test_errors_with_get_config
    res = @driver.get_config(@user, "a_config")
    assert_instance_of(DynamicConfig, res)
    assert_exception("NoMethodError", "undefined method `get_config'")
  end

  def test_errs_with_get_experiment
    res = @driver.get_experiment(@user, "an_experiment")
    assert_instance_of(DynamicConfig, res)
    assert_exception("NoMethodError", "undefined method `get_config'")
  end

  def test_errors_with_get_layer
    res = @driver.get_layer(@user, "a_layer")
    assert_instance_of(Layer, res)
    assert_exception("NoMethodError", "undefined method `get_layer'")
  end

  def test_errors_with_log_event
    @driver.log_event(@user, "an_event")
    assert_exception("NoMethodError", "undefined method `log_event'")
  end

  def test_errors_with_initialize
    opts = MiniTest::Mock.new
    opts.expect(:is_a?, true, [StatsigOptions])
    (0..3).each {
      opts.expect(:nil?, false)
    }

    opts.expect(:instance_of?, true, [StatsigOptions])

    StatsigDriver.new("secret-key", opts)
    assert_exception("NoMethodError", "unmocked method :api_url_base")
  end

  def test_errors_with_shutdown
    @driver.shutdown
    assert_exception("NoMethodError", "undefined method `shutdown' for 1:Integer")
  end

  private

  def assert_exception(type, trace)
    assert_requested(:post, 'https://statsigapi.net/v1/sdk_exception', :times => 1) do |req|
      body = JSON.parse(req.body)
      assert_equal(type, body["exception"])
      assert(body["info"].include?(trace))
    end
  end

end