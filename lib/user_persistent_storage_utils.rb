require 'statsig_options'

module Statsig
  class UserPersistentStorageUtils

    attr_accessor :cache

    attr_accessor :storage

    def initialize(options)
      @storage = options.user_persistent_storage
      @cache = {}
    end

    def get_user_persisted_values(user, id_type)
      key = self.class.get_storage_key(user, id_type)
      return @cache[key] unless @cache[key].nil?

      return load_from_storage(key)
    end

    def load_from_storage(key)
      return if @storage.nil?

      begin
        storage_values = @storage.load(key)
      rescue StandardError => e
        puts "Failed to load key (#{key}) from user_persisted_storage (#{e.message})"
        return nil
      end

      unless storage_values.nil?
        parsed_values = self.class.parse(storage_values)
        unless parsed_values.nil?
          @cache[key] = parsed_values
          return @cache[key]
        end
      end
      return nil
    end

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

    def remove_experiment_from_storage(user, id_type, config_name)
      persisted_values = get_user_persisted_values(user, id_type)
      unless persisted_values.nil?
        persisted_values.delete(config_name)
        save_to_storage(user, id_type, persisted_values)
      end
    end

    def add_evaluation_to_user_persisted_values(user_persisted_values, config_name, evaluation)
      if user_persisted_values.nil?
        user_persisted_values = {}
      end
      user_persisted_values[config_name] = evaluation.to_hash
    end

    private

    def self.parse(values_string)
      return JSON.parse(values_string)
    rescue JSON::ParserError
      return nil
    end

    def self.stringify(values_object)
      return JSON.generate(values_object)
    rescue StandardError
      return nil
    end

    def self.get_storage_key(user, id_type)
      "#{user.get_unit_id(id_type)}:#{id_type}"
    end
  end
end
