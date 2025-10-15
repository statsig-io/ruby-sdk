require 'json'
require_relative 'constants'
##
#  The user object to be evaluated against your Statsig configurations (gates/experiments/dynamic configs).
class StatsigUser

  # An identifier for this user. Evaluated against the User ID criteria. (https://docs.statsig.com/feature-gates/conditions#userid)
  attr_reader :user_id
  def user_id=(value)
    value_changed()
    @user_id = value
  end

  # An identifier for this user. Evaluated against the Email criteria. (https://docs.statsig.com/feature-gates/conditions#email)
  attr_reader :email
  def email=(value)
    value_changed()
    @email = value
  end

  # An IP address associated with this user. Evaluated against the IP Address criteria. (https://docs.statsig.com/feature-gates/conditions#ip)
  attr_reader :ip
  def ip=(value)
    value_changed()
    @ip = value
  end

  # A user agent string associated with this user. Evaluated against Browser Version and Name (https://docs.statsig.com/feature-gates/conditions#browser-version)
  attr_reader :user_agent
  def user_agent=(value)
    value_changed()
    @user_agent = value
  end

  # The country code associated with this user (e.g New Zealand => NZ). Evaluated against the Country criteria. (https://docs.statsig.com/feature-gates/conditions#country)
  attr_reader :country
  def country=(value)
    value_changed()
    @country = value
  end

  # An locale for this user.
  attr_reader :locale
  def locale=(value)
    value_changed()
    @locale = value
  end

  # The current app version the user is interacting with. Evaluated against the App Version criteria. (https://docs.statsig.com/feature-gates/conditions#app-version)
  attr_reader :app_version
  def app_version=(value)
    value_changed()
    @app_version = value
  end

  # A Hash you can use to set environment variables that apply to this user. e.g. { "tier" => "development" }
  attr_reader :statsig_environment
  def statsig_environment=(value)
    value_changed()
    @statsig_environment = value
  end

  # Any Custom IDs to associated with the user. (See https://docs.statsig.com/guides/experiment-on-custom-id-types)
  attr_reader :custom_ids
  def custom_ids=(value)
    value_changed()
    @custom_ids = value
  end

  # Any value you wish to use in evaluation, but do not want logged with events, can be stored in this field.
  attr_reader :private_attributes
  def private_attributes=(value)
    value_changed()
    @private_attributes = value
  end

  def custom
    @custom
  end

  # Any custom fields for this user. Evaluated against the Custom criteria. (https://docs.statsig.com/feature-gates/conditions#custom)
  def custom=(value)
    value_changed()
    @custom = value.is_a?(Hash) ? value : Hash.new
  end

  attr_accessor :memo_timeout

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
    @memo = {}
    @dirty = true
    @memo_timeout = 2
  end

  def serialize(for_logging)
    hash = {
      :userID => @user_id,
      :email => @email,
      :ip => @ip,
      :userAgent => @user_agent,
      :country => @country,
      :locale => @locale,
      :appVersion => @app_version,
      :custom => @custom,
      :statsigEnvironment => @statsig_environment,
      :privateAttributes => @private_attributes,
      :customIDs => @custom_ids,
    }
    if for_logging
      hash.delete(:privateAttributes)
    end
    hash.compact
  end

  def to_hash_without_stable_id
    hash = {}

    if @user_id != nil
      hash[:userID] = @user_id
    end
    if @email != nil
      hash[:email] = @email
    end
    if @ip != nil
      hash[:ip] = @ip
    end
    if @user_agent != nil
      hash[:userAgent] = @user_agent
    end
    if @country != nil
      hash[:country] = @country
    end
    if @locale != nil
      hash[:locale] = @locale
    end
    if @app_version != nil
      hash[:appVersion] = @app_version
    end
    if @custom != nil
      hash[:custom] = Statsig::HashUtils.sortHash(@custom)
    end
    if @statsig_environment != nil
      hash[:statsigEnvironment] = @statsig_environment.clone.sort_by { |key| key }.to_h
    end
    if @private_attributes != nil
      hash[:privateAttributes] = Statsig::HashUtils.sortHash(@private_attributes)
    end
    custom_ids = {}
    if @custom_ids != nil
      custom_ids = @custom_ids.clone
      if custom_ids.key?("stableID")
        custom_ids.delete("stableID")
      end
    end
    hash[:customIDs] = custom_ids.sort_by { |key| key }.to_h
    return Statsig::HashUtils.djb2ForHash(hash.sort_by { |key| key }.to_h)
  end

  def get_unit_id(id_type)
    if id_type.is_a?(String) && id_type != Statsig::Const::CML_USER_ID
      return nil unless @custom_ids.is_a? Hash

      return @custom_ids[id_type] || @custom_ids[id_type.downcase]
    end
    @user_id
  end

  def get_memo
    current_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  
    if @dirty || current_time - (@memo_access_time ||= current_time) > @memo_timeout
      if @memo.size() > 0
        @memo.clear
      end
      @dirty = false
      @memo_access_time = current_time
    end
  
    @memo
  end

  def clear_memo
    @memo.clear
    @dirty = false
    @memo_access_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def user_key
    unless !@dirty && defined? @_user_key
      custom_id_key = ''
      if self.custom_ids.is_a?(Hash)
        custom_id_key = self.custom_ids.values.join(',')
      end
      user_id_key = ''
      unless self.user_id.nil?
        user_id_key = self.user_id.to_s
      end
      @_user_key = user_id_key + ',' + custom_id_key.to_s
    end
    @_user_key
  end

  private
  def value_changed
    @dirty = true
  end 

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
