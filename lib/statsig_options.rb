class StatsigOptions
  attr_reader :environment

  def initialize(environment)
    @environment = environment.is_a?(Hash) ? environment : nil
  end
end