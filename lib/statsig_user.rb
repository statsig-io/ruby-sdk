class StatsigUser
  attr_accessor :user_id
  attr_accessor :email
  attr_accessor :ip
  attr_accessor :user_agent
  attr_accessor :country
  attr_accessor :locale
  attr_accessor :app_version
  attr_accessor :statsig_environment

  def custom
    @custom
  end

  def custom=(value)
    @custom = value.is_a?(Hash) ? value : Hash.new
  end

  def initialize(user_hash)
    @statsig_environment = Hash.new
    if user_hash.is_a?(Hash)
      @user_id = user_hash['userID'] || user_hash['user_id']
      @user_id = @user_id.to_s unless @user_id.nil?
      @email = user_hash['email']
      @ip = user_hash['ip']
      @user_agent = user_hash['userAgent'] || user_hash['user_agent']
      @country = user_hash['country']
      @locale = user_hash['locale']
      @app_version = user_hash['appVersion'] || user_hash['app_version']
      @custom = user_hash['custom']
      @statsig_environment = user_hash['statsigEnvironment']
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
      'appVersion' => @app_version,
      'custom' => @custom,
      'statsigEnvironment' => @statsig_environment,
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
      'appVersion' => @app_version,
      'appversion' => @app_version,
      'app_version' => @app_version,
      'custom' => @custom,
    }
  end
end