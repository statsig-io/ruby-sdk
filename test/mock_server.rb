
require 'sinatra/base'

MIN_DCS_REQUEST_TIME = 3
# Lives on http://localhost:4567
class MockApp < Sinatra::Base
  get '/v1/download_config_specs' do
    sleep MIN_DCS_REQUEST_TIME
  end
end

class MockServer
  def self.start_server(retries: 5)
    @thread = Thread.new do
      MockApp.run!
    rescue Errno::EADDRINUSE
      raise unless retries.positive?

      puts 'Port in use. Retrying in 1s...'
      sleep 1
      MockServer.start_server(retries: retries - 1)
    end
    sleep 0.1 until MockApp.running? || !@thread.alive?
  end

  def self.stop_server
    MockApp.stop!
    @thread.kill.join
    sleep 1 # needs some time for sinatra to free the port
  end
end
