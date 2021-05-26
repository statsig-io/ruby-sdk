class StatsigLogger
  def initialize(network, statsig_metadata)
    @network = network
    @statsig_metadata = statsig_metadata
    @events = []
  end

  def log_event(event)
    @events.push(event)
    if @events.length >= 500
      flush()
    end
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