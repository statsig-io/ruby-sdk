require 'minitest/autorun'
require 'minitest/mock'
require_relative '../lib/evaluation_details'

class EvaluationDetailsPrecisionTest < Minitest::Test
  def test_server_time_preserves_milliseconds_as_a_string
    [
      [0, '1631638014000'],
      [811_999, '1631638014811'],
      [999_999, '1631638014999'],
    ].each do |microseconds, expected|
      Time.stub(:now, Time.at(1_631_638_014, microseconds)) do
        details = Statsig::EvaluationDetails.new(1, 2, Statsig::EvaluationReason::NETWORK)

        assert_equal(expected, details.server_time)
      end
    end
  end
end
