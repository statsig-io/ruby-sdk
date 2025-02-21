require 'minitest/autorun'
require 'concurrent-ruby'
require 'statsig'

class TTLSetTest < Minitest::Test
  def setup
    @ttl_set = Statsig::TTLSet.new
    @ttl_set.instance_variable_set(:@reset_interval, 1)
    @ttl_set.instance_variable_set(:@background_reset, nil)  # Stop the old thread
    @ttl_set.instance_variable_set(:@background_reset, @ttl_set.periodic_reset)
  end

  def teardown
    @ttl_set.shutdown
  end

  def test_add_and_contains
    @ttl_set.add('test_key')
    assert @ttl_set.contains?('test_key'), "TTLSet should contain 'test_key' after adding"
  end

  def test_does_not_contain_unadded_key
    refute @ttl_set.contains?('missing_key'), "TTLSet should not contain a key that wasn't added"
  end

  def test_periodic_reset
    @ttl_set.add('key_to_reset')
    assert @ttl_set.contains?('key_to_reset'), "TTLSet should contain the key before reset"

    sleep(1.1)

    refute @ttl_set.contains?('key_to_reset'), "TTLSet should not contain the key after reset"
  end

  def test_shutdown_stops_reset_thread
    reset_thread = @ttl_set.instance_variable_get(:@background_reset)
    assert reset_thread.alive?, "Background reset thread should be running"

    @ttl_set.shutdown
    sleep(0.1)
    refute reset_thread.alive?, "Background reset thread should be stopped after shutdown"
  end
end
