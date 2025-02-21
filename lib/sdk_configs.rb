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
      @flags[flag] == true
    end

    def get_config_num_value(config)
      value = @configs[config]
      value.is_a?(Numeric) ? value.to_f : nil
    end
  end
end