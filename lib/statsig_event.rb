class StatsigEvent
  attr_accessor :value
  attr_accessor :user
  attr_accessor :metadata
  attr_accessor :statsig_metadata
  def initialize(event_name)
    @event_name = event_name
    @time = Time.now.to_f * 1000
  end

  def user=(value)
    @user = value
    @user.private_attributes = nil
  end

  def serialize
    private_user = @user
    private_user.private_attributes = nil
    return {
      'eventName' => @event_name,
      'metadata' => @metadata,
      'value' => @value,
      'user' => private_user,
      'time' => @time,
      'statsigMetadata' => @statsig_metadata,
    }
  end
end