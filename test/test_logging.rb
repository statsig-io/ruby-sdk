require 'minitest'
require 'minitest/autorun'
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
end