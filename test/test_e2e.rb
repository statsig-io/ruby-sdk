require 'minitest'
require 'minitest/autorun'
require 'statsig'

class TestE2E < Minitest::Test
  def before_setup
    super
    Statsig.shutdown
  end

  def test1
    puts Env["test_users"]
    assert(Env["test_users"] == "test")
  end
end