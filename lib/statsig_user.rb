class StatsigUser
  attr_accessor :user_id
  attr_accessor :email
  attr_accessor :ip
  attr_accessor :user_agent
  attr_accessor :country
  attr_accessor :locale
  attr_accessor :client_version

  def custom
    @custom
  end

  def custom=(value)
    @custom = value.is_a?(Hash) ? value : Hash.new
  end

  def serialize
    {
      'userID' => @user_id,
      'email' => @email,
      'ip' => @ip,
      'userAgent' => @user_agent,
      'country' => @country,
      'locale' => @locale,
      'clientVersion' => @client_version,
      'custom' => @custom,
    }
  end

  def value_lookup
    {
      'userID' => @user_id,
      'userid' => @user_id,
      'user_id' => @user_id,
      'email' => @email,
      'ip' => @ip,
      'userAgent' => @user_agent,
      'useragent' => @user_agent,
      'user_agent' => @user_agent,
      'country' => @country,
      'locale' => @locale,
      'clientVersion' => @client_version,
      'clientversion' => @client_version,
      'client_version' => @client_version,
      'custom' => @custom,
    }
  end
end