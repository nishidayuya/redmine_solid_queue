require "test-unit"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "socket"

# Most of this plugin works while Rails boots, and Redmine's test environment
# overrides config.active_job.queue_adapter. So tests boot Redmine in child
# processes with RAILS_ENV=development and check them from outside.
module RedmineSolidQueueTestHelper
  REDMINE_ROOT = File.expand_path(ENV.fetch("REDMINE_ROOT", Dir.pwd))
  PLUGIN_NAME = "redmine_solid_queue"
  PLUGIN_PATH = File.join(REDMINE_ROOT, "plugins", PLUGIN_NAME)
  RAILS_ENV = "development"
  LOG_DIR = File.join(REDMINE_ROOT, "tmp", "#{PLUGIN_NAME}_test")
  RESULT_PREFIX = "#{PLUGIN_NAME}_test_result:"

  if !File.exist?(File.join(REDMINE_ROOT, "config", "environment.rb"))
    abort("Run tests in Redmine's root directory or set REDMINE_ROOT: #{REDMINE_ROOT}")
  end

  def setup
    super
    @spawned_processes = []
    FileUtils.mkdir_p(LOG_DIR)
    clean_solid_queue_tables
  end

  def teardown
    @spawned_processes.reverse_each do |process|
      stop_process(process)
      if !passed?
        puts("--- #{process[:log_path]}")
        puts(File.read(process[:log_path]))
      end
    end
    super
  end

  # Runs the code with `bin/rails runner` and returns the code's value, which
  # must be convertible to JSON. The code runs without query cache, so it can
  # poll the database.
  def rails_runner(code, env: {})
    wrapped_code = <<~RUBY
      result = ActiveRecord::Base.uncached do
        #{code}
      end
      puts(#{RESULT_PREFIX.dump} + JSON.generate(result))
    RUBY
    stdout, stderr, status = Open3.capture3(
      rails_env(env), "bin/rails", "runner", wrapped_code, chdir: REDMINE_ROOT,
    )
    assert_true(status.success?, "bin/rails runner failed:\n#{stdout}\n#{stderr}")
    line = stdout.lines.reverse_each.find { |l| l.start_with?(RESULT_PREFIX) }
    assert_not_nil(line, "bin/rails runner printed no result:\n#{stdout}\n#{stderr}")
    return JSON.parse(line.delete_prefix(RESULT_PREFIX))
  end

  def clean_solid_queue_tables
    rails_runner(<<~RUBY)
      # Executions are deleted by foreign keys with ON DELETE CASCADE.
      [
        SolidQueue::Job,
        SolidQueue::Process,
        SolidQueue::Pause,
        SolidQueue::Semaphore,
        SolidQueue::RecurringTask,
      ].each(&:delete_all)
      nil
    RUBY
  end

  # Waits until all of `kinds` are registered in solid_queue_processes, and
  # returns registered kinds.
  def wait_for_solid_queue_processes(kinds, timeout: 60)
    return rails_runner(<<~RUBY)
      deadline = Time.now + #{timeout}
      loop do
        kinds = SolidQueue::Process.pluck(:kind).sort
        break kinds if (#{kinds.inspect} - kinds).empty? || Time.now > deadline
        sleep(0.5)
      end
    RUBY
  end

  def solid_queue_process_kinds
    return rails_runner("SolidQueue::Process.pluck(:kind).sort")
  end

  def spawn_process(name, *command, env: {})
    log_path = File.join(LOG_DIR, "#{name}.log")
    pid = Process.spawn(
      rails_env(env), *command,
      chdir: REDMINE_ROOT, out: log_path, err: [:child, :out], pgroup: true,
    )
    process = {pid: pid, log_path: log_path, status: nil}
    @spawned_processes << process
    return process
  end

  # Sends TERM and returns Process::Status. Kills the process group if it
  # doesn't exit in time.
  def stop_process(process, timeout: 30)
    return process[:status] if process[:status]

    begin
      Process.kill(:TERM, process[:pid])
    rescue Errno::ESRCH
      # already exited
    end
    deadline = Time.now + timeout
    while Time.now < deadline
      _, status = Process.waitpid2(process[:pid], Process::WNOHANG)
      if status
        process[:status] = status
        break
      end
      sleep(0.5)
    end
    begin
      Process.kill(:KILL, -process[:pid])
      Process.waitpid(process[:pid]) if !process[:status]
    rescue Errno::ESRCH, Errno::ECHILD
      # whole process group already exited
    end
    return process[:status]
  end

  def available_port
    server = TCPServer.new("127.0.0.1", 0)
    return server.addr[1]
  ensure
    server&.close
  end

  def wait_for_http(process, port, timeout: 120)
    deadline = Time.now + timeout
    loop do
      _, status = Process.waitpid2(process[:pid], Process::WNOHANG)
      if status
        process[:status] = status
        flunk("Server exited before responding:\n#{File.read(process[:log_path])}")
      end
      begin
        return Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/"))
      rescue SystemCallError
        flunk("Server didn't respond in #{timeout} seconds") if Time.now > deadline
        sleep(0.5)
      end
    end
  end

  private

  def rails_env(env)
    return {"RAILS_ENV" => RAILS_ENV}.merge(env)
  end
end
