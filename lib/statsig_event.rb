class StatsigEvent
  attr_accessor :value
  attr_accessor :metadata
  attr_accessor :statsig_metadata
  attr_accessor :secondary_exposures
  attr_reader :user

  def initialize(event_name)
    @event_name = event_name
    @time = Time.now.to_f * 1000
  end

  def user=(value)
    if value.is_a?(StatsigUser)
      @user = value.serialize(true)
    end
  end

  def serialize
    {
      'eventName' => @event_name,
      'metadata' => @metadata,
      'value' => @value,
      'user' => @user,
      'time' => @time,
      'statsigMetadata' => @statsig_metadata,
      'secondaryExposures' => @secondary_exposures
    }
  end
end