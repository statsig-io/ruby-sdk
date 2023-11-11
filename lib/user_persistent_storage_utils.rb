# typed: false

require 'sorbet-runtime'
require 'statsig_options'

module Statsig
  UserPersistedValues = T.type_alias { T::Hash[String, Hash] }

  class UserPersistentStorageUtils
    extend T::Sig

    sig { returns(T::Hash[String, UserPersistedValues]) }
    attr_accessor :cache

    sig { returns(T.nilable(Interfaces::IUserPersistentStorage)) }
    attr_accessor :storage

    sig { params(options: StatsigOptions).void }
    def initialize(options)
      @storage = options.user_persistent_storage
      @cache = {}
    end

    sig { params(user: StatsigUser, id_type: String).returns(UserPersistedValues) }
    def get_user_persisted_values(user, id_type)
      key = self.class.get_storage_key(user, id_type)
      return @cache[key] unless @cache[key].nil?

      return load_from_storage(key)
    end

    sig { params(key: String).returns(T.nilable(UserPersistedValues)) }
    def load_from_storage(key)
      return if @storage.nil?

      begin
        storage_values = @storage.load(key)
      rescue StandardError => e
        puts "Failed to load key (#{key}) from user_persisted_storage (#{e.message})"
        return {}
      end

      unless storage_values.nil?
        parsed_values = self.class.parse(storage_values)
        unless parsed_values.nil?
          @cache[key] = parsed_values
          return @cache[key]
        end
      end
      return {}
    end

    sig { params(user: StatsigUser, id_type: String, user_persisted_values: UserPersistedValues).void }
    def save_to_storage(user, id_type, user_persisted_values)
      return if @storage.nil?

      key = self.class.get_storage_key(user, id_type)
      stringified = self.class.stringify(user_persisted_values)
      return if stringified.nil?

      begin
        @storage.save(key, stringified)
      rescue StandardError => e
        puts "Failed to save key (#{key}) to user_persisted_storage (#{e.message})"
      end
    end

    sig { params(user: StatsigUser, id_type: String).void }
    def remove_from_storage(user, id_type)
      return if @storage.nil?

      key = self.class.get_storage_key(user, id_type)

      @cache.delete(key)
      begin
        @storage.delete(key)
      rescue StandardError => e
        puts "Failed to delete key (#{key}) in user_persisted_storage (#{e.message})"
      end
    end

    sig { params(user_persisted_values: T.nilable(UserPersistedValues), config_name: String, evaluation: ConfigResult).void }
    def add_evaluation_to_user_persisted_values(user_persisted_values, config_name, evaluation)
      if user_persisted_values.nil?
        user_persisted_values = {}
      end
      user_persisted_values[config_name] = evaluation.to_hash
    end

    private

    sig { params(values_string: String).returns(T.nilable(UserPersistedValues)) }
    def self.parse(values_string)
      return JSON.parse(values_string)
    rescue JSON::ParserError
      return nil
    end

    sig { params(values_object: UserPersistedValues).returns(T.nilable(String)) }
    def self.stringify(values_object)
      return JSON.generate(values_object)
    rescue StandardError
      return nil
    end

    sig { params(user: StatsigUser, id_type: String).returns(String) }
    def self.get_storage_key(user, id_type)
      "#{user.get_unit_id(id_type)}:#{id_type}"
    end
  end
end
