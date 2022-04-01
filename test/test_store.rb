require 'minitest/autorun'
require 'spy'
require 'statsig'
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

  def wait_for
    timeout = 3
    start = Time.now
    x = yield
    until x
      if Time.now - start > timeout
        raise "Wait to long here. Timeout #{timeout} sec"
      end
      sleep(0.1)
      x = yield
    end
  end

  def test_1_store_sync
    stub_request(:post, 'https://api.statsig.com/v1/download_config_specs').
      to_return(status: 200, body: JSON.generate({
        'dynamic_configs' => [
          {'name' => 'config_1'},
          {'name' => 'config_2'}
        ],
        'feature_gates' => [
          {'name' => 'gate_1'},
          {'name' => 'gate_2'},
        ],
        'layer_configs' => [],
        'has_updates' => true,
        'id_lists' => {
          'list_1' => true,
        }
      })).times(1).then.
      to_return(status: 200, body: JSON.generate({
        'dynamic_configs' => [
          {'name' => 'config_1'},
        ],
        'feature_gates' => [
          {'name' => 'gate_1'},
        ],
        'layer_configs' => [],
        'has_updates' => true,
        'id_lists' => {
          'list_1' => true,
          'list_2' => true,
        }
      }))

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
    stub_request(:post, 'https://api.statsig.com/v1/get_id_lists').
      to_return(status: 200, body: JSON.generate(get_id_lists_responses[0])).times(1).then.
      to_return(status: 200, body: JSON.generate(get_id_lists_responses[1])).times(1).then.
      to_return(status: 200, body: JSON.generate(get_id_lists_responses[2])).times(1).then.
      to_return(status: 200, body: JSON.generate(get_id_lists_responses[3])).times(1).then.
      to_return(status: 200, body: JSON.generate(get_id_lists_responses[4]))

    list_1_responses = %W[+1\n -1\n+2\n +3\n 3 +3\n+4\n+5\n+4\n-4\n+6\n]
    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_1').
      to_return(status: 200, body: list_1_responses[0], headers: {'Content-Length' => list_1_responses[0].length}).times(1).then.
      to_return(status: 200, body: list_1_responses[1], headers: {'Content-Length' => list_1_responses[1].length}).times(1).then.
      to_return(status: 200, body: list_1_responses[2], headers: {'Content-Length' => list_1_responses[2].length}).times(1).then.
      to_return(status: 200, body: list_1_responses[3], headers: {'Content-Length' => list_1_responses[3].length}).times(1).then.
      to_return(status: 200, body: list_1_responses[4], headers: {'Content-Length' => list_1_responses[4].length})

    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_2').
      to_return(status: 200, body: "+a\n", headers: {'Content-Length' => 3}).times(1).then.
      to_return(status: 200, body: "", headers: {'Content-Length' => 0})

    stub_request(:get, 'https://statsigapi.net/ruby-test-idlist/list_3').
      to_return(status: 200, body: "+0\n", headers: {'Content-Length' => 3}).times(1).then.
      to_return(status: 200, body: "", headers: {'Content-Length' => 0})

    net = Statsig::Network.new('secret-abc', 'https://api.statsig.com/v1/', 1)
    store = Statsig::SpecStore.new(net, nil, 1, 1)

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

    wait_for do
      Statsig::IDList.new(get_id_lists_responses[1]['list_1'], Set.new(["2"])) == store.get_id_list('list_1')
    end
    assert_equal(Statsig::IDList.new(get_id_lists_responses[1]['list_1'], Set.new(["2"])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    wait_for do
      Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])) == store.get_id_list('list_1')
    end
    assert_equal(Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    wait_for do
      Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])) == store.get_id_list('list_1')
    end
    # list_1 not changed because response was pointing to the older url
    assert_equal(Statsig::IDList.new(get_id_lists_responses[2]['list_1'], Set.new(["3"])),
                 store.get_id_list('list_1'))
    assert_nil(store.get_id_list('list_2'))
    assert_nil(store.get_id_list('list_3'))

    wait_for do
      store.get_id_list('list_1') == nil
    end
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

    wait_for do
      Statsig::IDList.new(get_id_lists_responses[4]['list_1'], Set.new(%w[3 5 6])) == store.get_id_list('list_1')
    end
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
        {'name' => 'config_1'},
        {'name' => 'config_2'}
      ],
      'feature_gates' => [
        {'name' => 'gate_1'},
        {'name' => 'gate_2'},
      ],
      'layer_configs' => [],
      'has_updates' => true,
      'id_lists' => {}
    }
    stub_request(:post, 'https://api.statsig.com/v1/download_config_specs')
      .to_return(status: 200, body: JSON.generate(config_spec_mock_response))

    stub_request(:post, 'https://api.statsig.com/v1/get_id_lists')
      .to_return(status: 200, body: JSON.generate({}))

    net = Statsig::Network.new('secret-abc', 'https://api.statsig.com/v1/', 1)
    spy = Spy.on(net, :post_helper).and_call_through
    store = Statsig::SpecStore.new(net, nil, 1, 1)

    wait_for do
      spy.calls.size == 6
    end
    assert(6, spy.calls.size) # download_config_specs were called 3 times + get_id_lists 3 time
    store.shutdown

    wait_for do
      spy.calls.size == 6
    end
    assert(6, spy.calls.size) # after shutdown no more call should be made
  end
end