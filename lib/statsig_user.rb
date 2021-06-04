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

  def initialize(user_hash = nil)
    if user_hash.is_a?(Hash)
      @user_id = user_hash['user_id']
      @email = user_hash['email']
      @ip = user_hash['ip']
      @user_agent = user_hash['user_agent']
      @country = user_hash['country']
      @locale = user_hash['locale']
      @client_version = user_hash['client_version']
      @custom = user_hash['custom']
    end
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