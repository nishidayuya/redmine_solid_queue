require_relative "helper"

class TestJobsCommand < Test::Unit::TestCase
  include RedmineSolidQueueTestHelper

  def test_start
    jobs = spawn_process("jobs", File.join("plugins", PLUGIN_NAME, "bin", "jobs"), "start")
    kinds = wait_for_solid_queue_processes(%w[Dispatcher Supervisor(fork) Worker])
    assert_equal(%w[Dispatcher Supervisor(fork) Worker], kinds)

    # DestroyProjectJob finishes without doing anything for missing users.
    active_job_id = rails_runner(<<~RUBY)
      DestroyProjectJob.perform_later(0, 0, "127.0.0.1").job_id
    RUBY
    finished = rails_runner(<<~RUBY)
      deadline = Time.now + 60
      loop do
        job = SolidQueue::Job.find_by!(active_job_id: #{active_job_id.dump})
        break true if job.finished?
        break false if job.failed? || Time.now > deadline
        sleep(0.5)
      end
    RUBY
    assert_true(finished, "job wasn't finished: #{active_job_id}")

    status = stop_process(jobs)
    assert_true(status&.success?, "bin/jobs didn't exit successfully: #{status.inspect}")
    assert_equal([], solid_queue_process_kinds)
  end
end
