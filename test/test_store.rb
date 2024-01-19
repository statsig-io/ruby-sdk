

require_relative 'test_helper'
require 'minitest/autorun'
require 'spy'
require 'statsig'
require 'minitest'
require 'webmock/minitest'

class TestStore < BaseTest
  suite :TestStore
  def setup
    super
    WebMock.enable!
    @diagnostics = Statsig::Diagnostics.new('test')
    @error_boundary = Statsig::ErrorBoundary.new('secret-key')
    @id_list_syncing_enabled = false
    @rulesets_syncing_enabled = false
  end

  def teardown
    super
    WebMock.reset!
    WebMock.disable!
  end

  def await_next_sync(check)
    return if check.call

    enable_id_list_syncing
    enable_rulesets_syncing
    timeout = 10
    start = Time.now

    while check.call != true
      if Time.now - start > timeout
        raise "Waited too long here. Timeout #{timeout} sec"
      end
    end

    sleep 0.1 # dont return immediately
  end

  def can_sync_id_lists
    @id_list_syncing_enabled
  end

  def disable_id_list_syncing
    @id_list_syncing_enabled = false
  end

  def enable_id_list_syncing
    @id_list_syncing_enabled = true
  end

  def can_sync_rulesets
    @rulesets_syncing_enabled
  end

  def disable_rulesets_syncing
    @rulesets_syncing_enabled = false
  end

  def enable_rulesets_syncing
    @rulesets_syncing_enabled = true
  end

  def test_1_store_sync
    dcs_calls = 0
    get_id_lists_calls = 0
    get_id_lists_calls_mutex = Mutex.new
    id_list_1_calls = 0
    id_list_1_calls_mutex = Mutex.new
    id_list_2_calls = 0
    id_list_2_calls_mutex = Mutex.new
    id_list_3_calls = 0
    id_list_3_calls_mutex = Mutex.new

    stub_download_config_specs.to_return { |req|
      if can_sync_rulesets
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

        disable_rulesets_syncing
        { body: JSON.generate(body) }
      end
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
      if can_sync_id_lists
        get_id_lists_calls_mutex.synchronize do
          index = [get_id_lists_calls, 4].min
          response = JSON.generate(get_id_lists_responses[index])
          get_id_lists_calls += 1

          disable_id_list_syncing

          puts "get_id_lists x#{get_id_lists_calls.to_s} Res:#{response}"
          { body: response }
        end
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

        puts "sync_list_1 x#{id_list_1_calls.to_s} Res:#{entry.gsub("\n", " ")}"

        { body: entry, headers: { 'Content-Length' => entry.length } }
      end
    }

    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_2').to_return { |req|
      id_list_2_calls_mutex.synchronize do
        id_list_2_calls += 1
        list_2_responses = [
          "+a\n",
          "",
        ]
        index = [id_list_2_calls, 2].min
        entry = list_2_responses[index - 1]

        puts "sync_list_2 x#{id_list_2_calls.to_s} Res:#{entry.gsub("\n", " ")}"

        { status: 200, body: entry, headers: { 'Content-Length' => entry.length } }
      end
    }

    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_3').to_return { |req|
      id_list_3_calls_mutex.synchronize do
        id_list_3_calls += 1
        list_3_responses = [
          "+0\n",
          "",
        ]
        index = [id_list_3_calls, 2].min
        entry = list_3_responses[index - 1]

        puts "sync_list_3 x#{id_list_3_calls.to_s} Res:#{entry.gsub("\n", " ")}"

        { status: 200, body: entry, headers: { 'Content-Length' => entry.length } }
      end
    }

    options = StatsigOptions.new(local_mode: false, rulesets_sync_interval: 0.2, idlists_sync_interval: 0.2)
    net = Statsig::Network.new('secret-abc', options, 1)
    logger = Statsig::StatsigLogger.new(net, options, @error_boundary)
    store = Statsig::SpecStore.new(net, options, nil, @diagnostics, @error_boundary, logger, 'secret-abc')
    spy_dcs = Spy.on(store, :download_config_specs).and_call_through_void
    spy_get_id_lists = Spy.on(store, :get_id_lists_from_network).and_call_through_void
    spy_download_single_id_list = Spy.on(store, :download_single_id_list).and_call_through_void

    puts ('await 1 across the board')
    assert_nothing_raised do
      await_next_sync(-> { return dcs_calls == 1 && get_id_lists_calls == 1 && id_list_1_calls == 1 })
    end
    wait_for do
      spy_dcs.finished? && spy_get_id_lists.finished? && spy_download_single_id_list.finished?
    end

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

    puts ('await 2 across the board')
    assert_nothing_raised do
      await_next_sync(-> { Statsig::IDList.new(get_id_lists_responses[1]['list_1'], Set.new(["2"])) == store.get_id_list('list_1') })
    end
    assert_equal(2, get_id_lists_calls)
    assert_equal(2, id_list_1_calls)
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    puts ('await 3 across the board')
    assert_nothing_raised do
      await_next_sync(-> { Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])) == store.get_id_list('list_1') })
    end
    assert_equal(3, get_id_lists_calls)
    assert_equal(3, id_list_1_calls)
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    puts ('await 4')
    await_next_sync(-> { return get_id_lists_calls == 4 })
    wait_for do
      spy_get_id_lists.finished?
    end

    # list_1 not changed because response was pointing to the older url
    assert_equal(Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    puts ('await 5')
    # list_1 is reset to nil because response gave an invalid string
    assert_nothing_raised do
      await_next_sync(lambda {
        Statsig::IDList.new({
                              'name' => 'list_3',
                              'size' => 3,
                              'url' => 'https://statsigapi.net/ruby-test-idlist/list_3',
                              'creationTime' => 5,
                              'fileID' => 'file_id_3',
                            }, Set.new(["0"])) == store.get_id_list('list_3') })
    end

    assert_equal(5, get_id_lists_calls)
    assert_equal(4, id_list_1_calls)
    assert_nil(store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))

    puts ('await 6')
    assert_nothing_raised do
      await_next_sync(lambda {
        Statsig::IDList.new(get_id_lists_responses[4]['list_1'], Set.new(%w[3 5 6])) == store.get_id_list('list_1') &&
        Statsig::IDList.new({
                              'name' => 'list_3',
                              'size' => 3,
                              'url' => 'https://statsigapi.net/ruby-test-idlist/list_3',
                              'creationTime' => 5,
                              'fileID' => 'file_id_3',
                            }, Set.new(["0"])) == store.get_id_list('list_3')
      })
    end
    assert_equal(6, get_id_lists_calls)
    assert_equal(5, id_list_1_calls)
    assert_nil(store.get_id_list('list_2'))
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
    stub_download_config_specs
      .to_return(status: 200, body: JSON.generate(config_spec_mock_response))

    stub_request(:post, 'https://statsigapi.net/v1/get_id_lists')
      .to_return(status: 200, body: JSON.generate({}))

    options = StatsigOptions.new(local_mode: false, rulesets_sync_interval: 1)
    net = Statsig::Network.new('secret-abc', options, 1)
    spy = Spy.on(net, :request).and_call_through
    logger = Statsig::StatsigLogger.new(net, options, @error_boundary)
    store = Statsig::SpecStore.new(net, options, nil, @diagnostics, @error_boundary, logger, 'secret-abc')

    wait_for do
      spy.calls.size == 6
    end
    assert_equal(6, spy.calls.size) # download_config_specs was called 3 times + get_id_lists 3 times
    store.shutdown

    wait_for do
      spy.calls.size == 6
    end
    assert_equal(6, spy.calls.size) # after shutdown no more call should be made
  end
end
