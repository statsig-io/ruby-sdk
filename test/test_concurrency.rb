# typed: true

require_relative 'test_helper'
require 'json'
require 'minitest'
require 'minitest/autorun'
require 'statsig'
require 'webmock/minitest'
require 'dynamic_config'
require 'layer'

class TestConcurrency < Minitest::Test
  json_file = File.read("#{__dir__}/data/download_config_specs.json")
  @@mock_response = JSON.parse(json_file).to_json

  @@flushed_event_count = 0
  @@flushed_event_count_mutex = Mutex.new
  @@idlist_sync_count = 0
  @@idlist_sync_count_mutex = Mutex.new
  @@download_idlist_count = 0
  @@download_idlist_count_mutex = Mutex.new

  def setup
    super
    WebMock.enable!
    Statsig.instance_variable_set("@shared_instance", nil)

    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return(status: 200, body: @@mock_response)
    stub_request(:post, 'https://statsigapi.net/v1/log_event').to_return(status: 200, body: lambda {|request|
      @@flushed_event_count_mutex.synchronize do
        @@flushed_event_count += JSON.parse(request.body)["events"].length
        return ''
      end
    })
    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return(status: 200, body: lambda {|get_id_lists_count|
        @@idlist_sync_count_mutex.synchronize do
          size = 10 + 3 * @@idlist_sync_count
          @@idlist_sync_count += 1
          return JSON.generate({
              'list_1' => {
                  'name' => 'list_1',
                  'size' => size,
                  'url' => 'https://statsigapi.net/list_1',
                  'creationTime' => 1,
                  'fileID' => 'file_id_1',
              }
          })
        end
    })
    stub_request(:get, 'https://statsigapi.net/list_1').to_return(status: 200,
      headers: { 'Content-Length' => get_id_list_response.length },
      body: lambda {|request|
        @@download_idlist_count_mutex.synchronize do
          res = get_id_list_response
          @@download_idlist_count += 1
          return res
        end
    })
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
    Statsig.shutdown
  end

  def get_id_list_response
    if @@download_idlist_count == 0
      "+7/rrkvF6\n"
    else
      "+#{@@download_idlist_count}\n-#{@@download_idlist_count}\n"
    end
  end

  def test_calling_apis_concurrently
    if ENV['CI']
      skip "Do not run on Github"
    end

    Statsig.initialize(
      'secret-testcase',
      StatsigOptions.new(rulesets_sync_interval: 0.01, idlists_sync_interval: 0.01, disable_diagnostics_logging: true)
    )
    threads = []
    10.times do
      threads << Thread.new do
        thread_id = rand(10000000000)
        100.times do |i|
          user = StatsigUser.new({'userID' => "user_id_#{i}", 'email' => 'testuser@statsig.com', customIDs: {'threadID' => "thread_id_#{thread_id}"}})

          Statsig.log_event(user, "test_event", 1, { 'price' => '9.99', 'item_name' => 'diet_coke_48_pack' })
          assert(Statsig.check_gate(user, 'always_on_gate') == true)
          assert(Statsig.check_gate(user, 'on_for_statsig_email') == true)
          # this check will get deduped across all threads, only the first exposure should be logged
          assert(Statsig.check_gate(StatsigUser.new({'userID' => 'regular_user_id'}), 'on_for_id_list') == true)
          assert(Statsig.check_gate(user, 'on_for_id_list') == false)
          Statsig.log_event(user, "test_event_2")
          exp_param = Statsig.get_experiment(user, 'sample_experiment').get('experiment_param', 'default')
          assert(exp_param == 'test' || exp_param == 'control')
          Statsig.log_event(user, "test_event_3", 'value')
          assert(Statsig.get_config(user, 'test_config').get('number', 0) == 7)
          layer = Statsig.get_layer(user, 'a_layer')
          assert(layer.get('layer_param', false) == true)
          assert(%w[control test].include?(layer.get('experiment_param', 'default')))
        end
      end
    end

    threads.each(&:join)
    Statsig.shutdown

    sleep 0.01

    assert_equal(10001, @@flushed_event_count)
  end

end