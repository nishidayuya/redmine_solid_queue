require_relative "helper"

class TestPumaPlugin < Test::Unit::TestCase
  include RedmineSolidQueueTestHelper

  def test_enabled
    start_server
    kinds = wait_for_solid_queue_processes(%w[Dispatcher Supervisor(fork) Worker])
    assert_equal(%w[Dispatcher Supervisor(fork) Worker], kinds)
  end

  def test_disabled
    start_server("REDMINE_SOLID_QUEUE_DISABLE_PUMA_PLUGIN" => "1")
    # Give the Puma plugin enough time to start a supervisor if it's enabled.
    sleep(10)
    assert_equal([], solid_queue_process_kinds)
  end

  private

  def start_server(env = {})
    port = available_port
    server = spawn_process(
      "server-#{name}",
      "bin/rails", "server", "--binding=127.0.0.1", "--port=#{port}",
      "--pid=#{File.join(LOG_DIR, "server.pid")}",
      env: env,
    )
    wait_for_http(server, port)
    return server
  end
end
