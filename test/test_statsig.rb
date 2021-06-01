require 'minitest'
require 'minitest/autorun'
require 'statsig'

class TestStatsig < Minitest::Test
  # def setup
  #   @statsig = Statsig.new('secret-key')
  # end

  def test_that_a_secret_must_be_provided
    assert_raises(Statsig.new(''))
  end
end