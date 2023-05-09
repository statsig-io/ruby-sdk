# typed: false

require_relative 'test_helper'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'minitest'
require 'webmock/minitest'

class TestStore < Minitest::Test
  def setup
    super
    WebMock.enable!
  end

  def teardown
    super
    WebMock.disable!
  end

  def await_next_id_sync(check)
    @id_list_syncing_enabled = true
    timeout = 10
    start = Time.now

    while check.call != true
      if Time.now - start > timeout
        raise "Waited too long here. Timeout #{timeout} sec"
      end
    end

    sleep 0.1 # dont return immediately
  end

  def wait_for
    timeout = 10
    start = Time.now
    x = yield
    until x
      if Time.now - start > timeout
        raise "Waited too long here. Timeout #{timeout} sec"
      end
      sleep(0.1)
      x = yield
    end
  end

  def can_sync_id_lists
    @id_list_syncing_enabled
  end

  def disable_id_list_syncing
    @id_list_syncing_enabled = false
  end

  def test_1_store_sync
    dcs_calls = 0
    get_id_lists_calls = 0
    get_id_lists_calls_mutex = Mutex.new
    id_list_1_calls = 0
    id_list_1_calls_mutex = Mutex.new

    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs').to_return { |req|
      dcs_calls += 1
      body = {
        'dynamic_configs' => [
          { 'name' => 'config_1' },
        ],
        'feature_gates' => [
          { 'name' => 'gate_1' },
        ],
        'layer_configs' => [],
        'has_updates' => true,
        'id_lists' => {
          'list_1' => true,
          'list_2' => true,
        }
      }

      if dcs_calls == 1
        body = {
          'dynamic_configs' => [
            { 'name' => 'config_1' },
            { 'name' => 'config_2' }
          ],
          'feature_gates' => [
            { 'name' => 'gate_1' },
            { 'name' => 'gate_2' },
          ],
          'layer_configs' => [],
          'has_updates' => true,
          'id_lists' => {
            'list_1' => true,
          }
        }
      end

      { body: JSON.generate(body) }
    }

    get_id_lists_responses = [
      #0, 2 lists initially
      {
        'list_1' => {
          'name' => 'list_1',
          'size' => 3,
          'url' => 'https://statsigapi.net/ruby-test-idlist/list_1',
          'creationTime' => 1,
          'fileID' => 'file_id_1',
        },
        'list_2' => {
          'name' => 'list_2',
          'size' => 3,
          'url' => 'https://statsigapi.net/ruby-test-idlist/list_2',
          'creationTime' => 1,
          'fileID' => 'file_id_2',
        }
      },
      #1, list_1 increased, list_2 deleted
      {
        'list_1' => {
          'name' => 'list_1',
          'size' => 9,
          'url' => 'https://statsigapi.net/ruby-test-idlist/list_1',
          'creationTime' => 1,
          'fileID' => 'file_id_1',
        }
      },
      #2, list_1 reset to new file
      {
        'list_1' => {
          'name' => 'list_1',
          'size' => 3,
          'url' => 'https://statsigapi.net/ruby-test-idlist/list_1',
          'creationTime' => 3,
          'fileID' => 'file_id_1_a',
        }
      },
      #3, returned old file for some reason
      {
        'list_1' => {
          'name' => 'list_1',
          'size' => 9,
          'url' => 'https://statsigapi.net/ruby-test-idlist/list_1',
          'creationTime' => 1,
          'fileID' => 'file_id_1',
        }
      },
      #4, return same list and another one afterwards
      {
        'list_1' => {
          'name' => 'list_1',
          'size' => 18,
          'url' => 'https://statsigapi.net/ruby-test-idlist/list_1',
          'creationTime' => 3,
          'fileID' => 'file_id_1_a',
        },
        'list_3' => {
          'name' => 'list_3',
          'size' => 3,
          'url' => 'https://statsigapi.net/ruby-test-idlist/list_3',
          'creationTime' => 5,
          'fileID' => 'file_id_3',
        }
      }
    ]

    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists').to_return { |req|
      get_id_lists_calls_mutex.synchronize do
        index = [get_id_lists_calls, 4].min
        response = JSON.generate(get_id_lists_responses[index])
        get_id_lists_calls += 1

        until can_sync_id_lists
        end

        disable_id_list_syncing

        puts "get_id_lists x" + get_id_lists_calls.to_s + " Res:" + response
        { body: response }
      end
    }

    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_1').to_return { |req|
      id_list_1_calls_mutex.synchronize do
        id_list_1_calls += 1
        list_1_responses = [
          "+1\n",
          "-1\n+2\n",
          "+3\n",
          "3", # corrupted
          "+3\n+4\n+5\n+4\n-4\n+6\n"
        ]
        index = [id_list_1_calls, 5].min
        entry = list_1_responses[index - 1]

        puts "sync_list_1 x" + id_list_1_calls.to_s + " Res:" + entry.gsub("\n", " ")

        { body: entry, headers: { 'Content-Length' => entry.length } }
      end
    }

    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_2').
      to_return(status: 200, body: "+a\n", headers: { 'Content-Length' => 3 }).times(1).then.
      to_return(status: 200, body: "", headers: { 'Content-Length' => 0 })

    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_3').
      to_return(status: 200, body: "+0\n", headers: { 'Content-Length' => 3 }).times(1).then.
      to_return(status: 200, body: "", headers: { 'Content-Length' => 0 })

    @id_list_syncing_enabled = true
    options = StatsigOptions.new(local_mode: false)
    net = Statsig::Network.new('secret-abc', options, 1)
    store = Statsig::SpecStore.new(net, StatsigOptions.new(rulesets_sync_interval: 0.2, idlists_sync_interval: 0.2), nil)

    puts ('await 1 across the board')
    await_next_id_sync(lambda { return dcs_calls == 1 && get_id_lists_calls == 1 && id_list_1_calls == 1 })

    assert(!store.get_config('config_1').nil?)
    assert(!store.get_config('config_2').nil?)
    assert(!store.get_gate('gate_1').nil?)
    assert(!store.get_gate('gate_2').nil?)
    assert_equal(Statsig::IDList.new(get_id_lists_responses[0]['list_1'], Set.new(["1"])),
                 store.get_id_list('list_1'))
    assert_equal(Statsig::IDList.new({
                                       'name' => 'list_2',
                                       'size' => 3,
                                       'url' => 'https://statsigapi.net/ruby-test-idlist/list_2',
                                       'creationTime' => 1,
                                       'fileID' => 'file_id_2',
                                     }, Set.new(["a"])), store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    await_next_id_sync(lambda { return get_id_lists_calls == 2 && id_list_1_calls == 2 })

    assert_equal(Statsig::IDList.new(get_id_lists_responses[1]['list_1'], Set.new(["2"])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    puts ('await 3 across the board')
    await_next_id_sync(lambda { return get_id_lists_calls == 3 && id_list_1_calls == 3 })

    assert_equal(Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    puts ('await 4')
    await_next_id_sync(lambda { return get_id_lists_calls == 4 })

    # list_1 not changed because response was pointing to the older url
    assert_equal(Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    puts ('await 5')
    await_next_id_sync(lambda { return get_id_lists_calls == 5 && id_list_1_calls == 4 })

    # list_1 is reset to nil because response gave an invalid string
    assert_nil(store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_equal(Statsig::IDList.new({
                                       'name' => 'list_3',
                                       'size' => 3,
                                       'url' => 'https://statsigapi.net/ruby-test-idlist/list_3',
                                       'creationTime' => 5,
                                       'fileID' => 'file_id_3',
                                     }, Set.new(["0"])), store.get_id_list('list_3'))

    puts ('await 6')
    await_next_id_sync(lambda { return get_id_lists_calls == 6 })

    assert_equal(Statsig::IDList.new(get_id_lists_responses[4]['list_1'], Set.new(%w[3 5 6])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_equal(Statsig::IDList.new({
                                       'name' => 'list_3',
                                       'size' => 3,
                                       'url' => 'https://statsigapi.net/ruby-test-idlist/list_3',
                                       'creationTime' => 5,
                                       'fileID' => 'file_id_3',
                                     }, Set.new(["0"])), store.get_id_list('list_3'))

    assert(!store.get_config('config_1').nil?)
    assert(store.get_config('config_2').nil?)
    assert(!store.get_gate('gate_1').nil?)
    assert(store.get_gate('gate_2').nil?)
  end

  def test_2_no_id_lists_sync
    config_spec_mock_response = {
      'dynamic_configs' => [
        { 'name' => 'config_1' },
        { 'name' => 'config_2' }
      ],
      'feature_gates' => [
        { 'name' => 'gate_1' },
        { 'name' => 'gate_2' },
      ],
      'layer_configs' => [],
      'has_updates' => true,
      'id_lists' => {}
    }
    stub_request(:post, 'https://statsigapi.net/v1/download_config_specs')
      .to_return(status: 200, body: JSON.generate(config_spec_mock_response))

    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists')
      .to_return(status: 200, body: JSON.generate({}))

    options = StatsigOptions.new(local_mode: false)
    net = Statsig::Network.new('secret-abc', options, 1)
    spy = Spy.on(net, :post_helper).and_call_through
    store = Statsig::SpecStore.new(net, StatsigOptions.new(rulesets_sync_interval: 1), nil)

    wait_for do
      spy.calls.size == 6
    end
    assert(6, spy.calls.size) # download_config_specs was called 3 times + get_id_lists 3 times
    store.shutdown

    wait_for do
      spy.calls.size == 6
    end
    assert(6, spy.calls.size) # after shutdown no more call should be made
  end
end
