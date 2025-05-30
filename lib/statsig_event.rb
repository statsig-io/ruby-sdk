class StatsigEvent
  attr_accessor :value, :metadata, :statsig_metadata, :secondary_exposures
  attr_reader :user

  def initialize(event_name)
    @event_name = event_name
    @value = nil
    @metadata = nil
    @secondary_exposures = nil
    @user = nil
    @time = (Time.now.to_f * 1000).to_i
    @statsig_metadata = Statsig.get_statsig_metadata
  end

  def user=(value)
    if value.is_a?(StatsigUser)
      @user = Statsig::Memo.for(value.get_memo(), :serialize, 0, disable_evaluation_memoization: Statsig.get_options&.disable_evaluation_memoization) do
        value.serialize(true)
      end
    end
  end

  def serialize
    {
      :eventName => @event_name,
      :metadata => @metadata,
      :value => @value,
      :user => @user,
      :time => @time,
      :statsigMetadata => @statsig_metadata,
      :secondaryExposures => @secondary_exposures
    }
  end
end