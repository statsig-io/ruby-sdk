class StatsigOptions
  attr_reader :environment
  attr_reader :api_url_base

  def initialize(environment = nil, api_url_base = 'https://statsigapi.net/v1')
    @environment = environment.is_a?(Hash) ? environment : nil
    @api_url_base = api_url_base
  end
end