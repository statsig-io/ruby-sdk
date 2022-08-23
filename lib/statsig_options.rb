class StatsigOptions
  attr_reader :environment
  attr_reader :api_url_base
  attr_reader :rulesets_sync_interval
  attr_reader :idlists_sync_interval
  attr_reader :logging_interval_seconds
  attr_reader :logging_max_buffer_size

  def initialize(
    environment=nil,
    api_url_base='https://statsigapi.net/v1',
    rulesets_sync_interval: 10,
    idlists_sync_interval: 60,
    logging_interval_seconds: 60,
    logging_max_buffer_size: 1000)
    @environment = environment.is_a?(Hash) ? environment : nil
    @api_url_base = api_url_base
    @rulesets_sync_interval = rulesets_sync_interval
    @idlists_sync_interval = idlists_sync_interval
    @logging_interval_seconds = logging_interval_seconds
    @logging_max_buffer_size = [logging_max_buffer_size, 1000].min
  end
end