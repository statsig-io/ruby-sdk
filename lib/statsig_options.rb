class StatsigOptions
  attr_accessor :environment
  attr_accessor :api_url_base
  attr_accessor :rulesets_sync_interval
  attr_accessor :idlists_sync_interval
  attr_accessor :logging_interval_seconds
  attr_accessor :logging_max_buffer_size
  attr_accessor :local_mode
  attr_accessor :bootstrap_values

  def initialize(
    environment=nil,
    api_url_base='https://statsigapi.net/v1',
    rulesets_sync_interval: 10,
    idlists_sync_interval: 60,
    logging_interval_seconds: 60,
    logging_max_buffer_size: 1000,
    local_mode: false,
    bootstrap_values: nil)
    @environment = environment.is_a?(Hash) ? environment : nil
    @api_url_base = api_url_base
    @rulesets_sync_interval = rulesets_sync_interval
    @idlists_sync_interval = idlists_sync_interval
    @logging_interval_seconds = logging_interval_seconds
    @logging_max_buffer_size = [logging_max_buffer_size, 1000].min
    @local_mode = local_mode
    @bootstrap_values = bootstrap_values
  end
end