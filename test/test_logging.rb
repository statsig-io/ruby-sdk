require 'minitest'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'webmock/minitest'

class TestLogging < Minitest::Test
  def before_setup
    super
  end

  def test_event_does_not_have_private_attributes
    user = StatsigUser.new({'userID' => '123', 'privateAttributes' => {'secret_value' => 'shhhhh'}})
    event = StatsigEvent.new('test')
    event.user = user
    assert(event.user['private_attributes'] == nil)
    assert(event.serialize.has_key?('privateAttributes') == false)
  end

  def test_exposure_event
    stub_request(:post, "https://api.statsig.com/v1/log_event").to_return(status: 200, body: "hello")

    @net = Network.new('secret-abc', 'https://api.statsig.com/v1/', 1)
    spy = Spy.on(@net, :post_logs).and_return
    @statsig_metadata = {
      'sdkType' => 'ruby-server',
      'sdkVersion' => Gem::Specification::load('statsig.gemspec')&.version,
    }
    @logger = StatsigLogger.new(@net)
    @logger.log_gate_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' }}),
      'test_gate',
      true,
      'gate_rule_id',
      [{
        "gate" => 'another_gate',
        "gateValue" => "true",
        "ruleID" => 'another_rule_id'
      }]
    )

    @logger.log_config_exposure(
      StatsigUser.new({ 'userID' => '123', 'privateAttributes' => { 'secret' => 'shhh' }}),
      'test_config',
      'config_rule_id',
      [{
        "gate" => 'another_gate_2',
        "gateValue" => "false",
        "ruleID" => 'another_rule_id_2'
      }]
    )
    @logger.flush

    assert(spy.calls[0].args[0].is_a?(Array))
    assert(spy.calls[0].args[0].size == 2)

    gate_exposure = spy.calls[0].args[0][0]
    assert(gate_exposure['eventName'] == 'statsig::gate_exposure')
    assert(gate_exposure['metadata'] == {"gate"=>"test_gate", "gateValue"=>"true", "ruleID"=>"gate_rule_id"})
    assert(gate_exposure['user']['userID'] == '123')
    assert(gate_exposure['user']['privateAttributes'] == nil)
    assert(gate_exposure['secondaryExposures'] == [{
      "gate" => 'another_gate',
      "gateValue" => "true",
      "ruleID" => 'another_rule_id'
    }])

    config_exposure = spy.calls[0].args[0][1]
    assert(config_exposure['eventName'] == 'statsig::config_exposure')
    assert(config_exposure['metadata'] == {"config"=>"test_config", "ruleID"=>"config_rule_id"})
    assert(config_exposure['user']['userID'] == '123')
    assert(config_exposure['user']['privateAttributes'] == nil)
    assert(config_exposure['secondaryExposures'] == [{
      "gate" => 'another_gate_2',
      "gateValue" => "false",
      "ruleID" => 'another_rule_id_2'
    }])
  end
end