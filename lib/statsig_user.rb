# typed: true

require 'sorbet-runtime'

##
#  The user object to be evaluated against your Statsig configurations (gates/experiments/dynamic configs).
class StatsigUser
  extend T::Sig

  sig { returns(T.any(String, NilClass)) }
  # An identifier for this user. Evaluated against the User ID criteria. (https://docs.statsig.com/feature-gates/conditions#userid)
  attr_accessor :user_id

  sig { returns(T.any(String, NilClass)) }
  # An identifier for this user. Evaluated against the Email criteria. (https://docs.statsig.com/feature-gates/conditions#email)
  attr_accessor :email

  sig { returns(T.any(String, NilClass)) }
  # An IP address associated with this user. Evaluated against the IP Address criteria. (https://docs.statsig.com/feature-gates/conditions#ip)
  attr_accessor :ip

  sig { returns(T.any(String, NilClass)) }
  # A user agent string associated with this user. Evaluated against Browser Version and Name (https://docs.statsig.com/feature-gates/conditions#browser-version)
  attr_accessor :user_agent

  sig { returns(T.any(String, NilClass)) }
  # The country code associated with this user (e.g New Zealand => NZ). Evaluated against the Country criteria. (https://docs.statsig.com/feature-gates/conditions#country)
  attr_accessor :country

  sig { returns(T.any(String, NilClass)) }
  # An locale for this user.
  attr_accessor :locale

  sig { returns(T.any(String, NilClass)) }
  # The current app version the user is interacting with. Evaluated against the App Version criteria. (https://docs.statsig.com/feature-gates/conditions#app-version)
  attr_accessor :app_version

  sig { returns(T.any(T::Hash[String, String], NilClass)) }
  # A Hash you can use to set environment variables that apply to this user. e.g. { "tier" => "development" }
  attr_accessor :statsig_environment

  sig { returns(T.any(T::Hash[String, String], NilClass)) }
  # Any Custom IDs to associated with the user. (See https://docs.statsig.com/guides/experiment-on-custom-id-types)
  attr_accessor :custom_ids

  sig { returns(T.any(T::Hash[String, String], NilClass)) }
  # Any value you wish to use in evaluation, but do not want logged with events, can be stored in this field.
  attr_accessor :private_attributes

  sig { returns(T.any(T::Hash[String, T.untyped], NilClass)) }
  def custom
    @custom
  end

  sig { params(value: T.any(T::Hash[String, T.untyped], NilClass)).void }
  # Any custom fields for this user. Evaluated against the Custom criteria. (https://docs.statsig.com/feature-gates/conditions#custom)
  def custom=(value)
    @custom = value.is_a?(Hash) ? value : Hash.new
  end

  sig { params(user_hash: T.any(T::Hash[String, T.untyped], NilClass)).void }

  def initialize(user_hash)
    @user_id = nil
    @email = nil
    @ip = nil
    @user_agent = nil
    @country = nil
    @locale = nil
    @app_version = nil
    @custom = nil
    @private_attributes = nil
    @custom_ids = nil
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
    hash.compact
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