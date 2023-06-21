# typed: ignore
require 'sinatra/base'

MIN_DCS_REQUEST_TIME = 3
# Lives on http://localhost:4567
class MockApp < Sinatra::Base
  post '/v1/download_config_specs' do
    sleep MIN_DCS_REQUEST_TIME
  end
end

class MockServer
  def self.start_server
    @thread = Thread.new do
      MockApp.run!
    end
    sleep 1
  end

  def self.stop_server
    MockApp.stop!
    @thread.kill.join
    sleep 0.1 # needs some time for sinatra to free the port
  end
end
