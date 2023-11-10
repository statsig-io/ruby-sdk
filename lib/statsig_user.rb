# typed: true

require 'sorbet-runtime'
require 'json'

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

  sig { params(user_hash: T.any(T::Hash[T.any(String, Symbol), T.untyped], NilClass)).void }
  def initialize(user_hash)
    the_hash = user_hash
    begin
      the_hash = JSON.parse(user_hash&.to_json || "")
    rescue
      puts 'Failed to clone user hash'
    end

    @user_id = from_hash(the_hash, [:user_id, :userID], String)
    @email = from_hash(the_hash, [:email], String)
    @ip = from_hash(the_hash, [:ip], String)
    @user_agent = from_hash(the_hash, [:user_agent, :userAgent], String)
    @country = from_hash(the_hash, [:country], String)
    @locale = from_hash(the_hash, [:locale], String)
    @app_version = from_hash(the_hash, [:app_version, :appVersion], String)
    @custom = from_hash(the_hash, [:custom], Hash)
    @private_attributes = from_hash(the_hash, [:private_attributes, :privateAttributes], Hash)
    @custom_ids = from_hash(the_hash, [:custom_ids, :customIDs], Hash)
    @statsig_environment = from_hash(the_hash, [:statsig_environment, :statsigEnvironment], Hash)
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

  def to_hash_without_stable_id()
    hash = {}
    if @user_id != nil
      hash['userID'] = @user_id
    end
    if @email != nil
      hash['email'] = @email
    end
    if @ip != nil
      hash['ip'] = @ip
    end
    if @user_agent != nil
      hash['userAgent'] = @user_agent
    end
    if @country != nil
      hash['country'] = @country
    end
    if @locale != nil
      hash['locale'] = @locale
    end
    if @app_version != nil
      hash['appVersion'] = @app_version
    end
    if @custom != nil
      hash['custom'] = Statsig::HashUtils.sortHash(@custom)
    end
    if @statsig_environment != nil
      hash['statsigEnvironment'] = @statsig_environment.clone.sort_by { |key| key }.to_h
    end
    if @private_attributes != nil
      hash['privateAttributes'] = Statsig::HashUtils.sortHash(@private_attributes)
    end
    custom_ids = {}
    if @custom_ids != nil
      custom_ids = @custom_ids.clone
      if custom_ids.key?("stableID")
        custom_ids.delete("stableID")
      end
    end
    hash['customIDs'] = custom_ids.sort_by { |key| key }.to_h
    return Statsig::HashUtils.djb2ForHash(hash.sort_by { |key| key }.to_h)
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

  def get_unit_id(id_type)
    if id_type.is_a?(String) && id_type.downcase != 'userid'
      return nil unless @custom_ids.is_a? Hash

      return @custom_ids[id_type] || @custom_ids[id_type.downcase]
    end
    @user_id
  end

  private

  sig {
    params(user_hash: T.any(T::Hash[T.any(String, Symbol), T.untyped], NilClass),
           keys: T::Array[Symbol],
           type: T.untyped)
      .returns(T.untyped)
  }
  # Pulls fields from the user hash via Symbols and Strings
  def from_hash(user_hash, keys, type)
    if user_hash.nil?
      return nil
    end

    keys.each do |key|
      val = user_hash[key] || user_hash[key.to_s]
      if not val.nil? and val.is_a? type
        return val
      end
    end

    nil
  end
end
