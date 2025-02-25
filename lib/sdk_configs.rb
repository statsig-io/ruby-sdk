require 'concurrent-ruby'

module Statsig
  class SDKConfigs
    def initialize
      @configs = Concurrent::Hash.new
      @flags = Concurrent::Hash.new
    end

    def set_flags(new_flags)
      @flags = new_flags || Concurrent::Hash.new
    end

    def set_configs(new_configs)
      @configs = new_configs || Concurrent::Hash.new
    end

    def on(flag)
      @flags[flag.to_sym] == true
    end

    def get_config_num_value(config)
      value = @configs[config.to_sym]
      value.is_a?(Numeric) ? value.to_f : nil
    end

    def get_config_string_value(config)
      value = @configs[config.to_sym]
      value.is_a?(String) ? value : nil
    end

    def get_config_int_value(config)
      value = @configs[config.to_sym]
      value.is_a?(Integer) ? value : nil
    end
  end
end
