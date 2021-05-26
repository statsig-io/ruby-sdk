require 'concurrent'
require 'http'
require 'json'

class Network
    include Concurrent::Async

    def initialize(server_secret, api)
        super()
        @http = HTTP
            .headers({"STATSIG-API-KEY" => server_secret, "Content-Type" => "application/json; charset=UTF-8"})
            .accept(:json)
        @api = api
    end

  def check_gate(gate_name)
    uri = URI(@api + '/check_gate')

    response =  @http.post(@api + '/check_gate', body: JSON.generate({'gateName' => gate_name}))
    puts response
    gate = JSON.parse(response.body)
    sleep(2)
    return false if gate.nil? || gate['value'].nil?
    gate['value']
  end
end