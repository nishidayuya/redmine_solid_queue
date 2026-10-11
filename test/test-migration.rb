require_relative "helper"

class TestMigration < Test::Unit::TestCase
  include RedmineSolidQueueTestHelper

  def test_tables
    tables = rails_runner(<<~RUBY)
      ActiveRecord::Base.connection.tables.grep(/\\Asolid_queue_/).sort
    RUBY
    assert_equal(
      %w[
        solid_queue_blocked_executions
        solid_queue_claimed_executions
        solid_queue_failed_executions
        solid_queue_jobs
        solid_queue_pauses
        solid_queue_processes
        solid_queue_ready_executions
        solid_queue_recurring_executions
        solid_queue_recurring_tasks
        solid_queue_scheduled_executions
        solid_queue_semaphores
      ],
      tables,
    )
  end
end
