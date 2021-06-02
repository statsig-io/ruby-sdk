require 'statsig_event'

$gate_exposure_event = 'statsig::gate_exposure'
$config_exposure_event = 'statsig::config_exposure'

class StatsigLogger
  def initialize(network, statsig_metadata)
    @network = network
    @statsig_metadata = statsig_metadata
    @events = []
  end

  def log_event(event)
    @events.push(event)
    if @events.length >= 500
      flush
    end
  end

  def log_gate_exposure(user, gate_name, value, rule_id)
    event = StatsigEvent.new($gate_exposure_event)
    event.user = user
    event.metadata = {
      'gate' => gate_name,
      'gateValue' => value.to_s,
      'ruleID' => rule_id
    }
    event.statsig_metadata = @statsig_metadata
    log_event(event)
  end

  def log_config_exposure(user, config_name, rule_id)
    event = StatsigEvent.new($config_exposure_event)
    event.user = user
    event.metadata = {
      'config' => config_name,
      'ruleID' => rule_id
    }
    event.statsig_metadata = @statsig_metadata
    log_event(event)
  end

  def flush
    if @events.length == 0
      return
    end
    flush_events = @events.map { |e| e.serialize() }
    @events = []

    @network.post_logs(flush_events, @statsig_metadata)
  end
end