class StatsigUser
  attr_accessor :user_id
  attr_accessor :email
  attr_accessor :ip
  attr_accessor :user_agent
  attr_accessor :country
  attr_accessor :locale
  attr_accessor :app_version
  attr_accessor :statsig_environment
  attr_accessor :custom_ids
  attr_accessor :private_attributes

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
      @custom = user_hash['custom'] if user_hash['custom'].is_a? Hash
      @statsig_environment = user_hash['statsigEnvironment']
      @private_attributes = user_hash['privateAttributes'] if user_hash['privateAttributes'].is_a? Hash
      custom_ids = user_hash['customIDs'] || user_hash['custom_ids']
      @custom_ids = custom_ids if custom_ids.is_a? Hash
    end
  end

  def serialize(for_logging)
    hash = {
      'userID' => @user_id,
      'email' => @email,
      'ip' => @ip,
      'userAgent' => @user_agent,
      'country' => @country,
      'locale' => @locale,
      'appVersion' => @app_version,
      'custom' => @custom,
      'statsigEnvironment' => @statsig_environment,
      'privateAttributes' => @private_attributes,
      'customIDs' => @custom_ids,
    }
    if for_logging
      hash.delete('privateAttributes')
    end
    hash
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
      'privateAttributes' => @private_attributes,
    }
  end
end