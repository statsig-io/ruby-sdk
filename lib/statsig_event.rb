class StatsigEvent
  attr_accessor :value
  attr_accessor :user
  attr_accessor :metadata
  attr_accessor :statsig_metadata
  def initialize(event_name)
    @event_name = event_name
    @time = Time.now.to_i * 1000
  end

  def serialize
    return {
      'eventName' => @event_name,
      'metadata' => @metadata,
      'value' => @value,
      'user' => @user,
      'time' => @time,
      'statsigMetadata' => @statsig_metadata,
    }
  end
end