require_relative "helper"

class TestQueueAdapter < Test::Unit::TestCase
  include RedmineSolidQueueTestHelper

  ADDITIONAL_ENVIRONMENT_PATH =
    File.join(RedmineSolidQueueTestHelper::REDMINE_ROOT, "config", "additional_environment.rb")

  def test_default
    assert_equal(
      {
        "queue_adapter_name" => "solid_queue",
        # Redmine shows it as "Mailer queue" on /admin/info
        "mailer_queue_adapter" => "ActiveJob::QueueAdapters::SolidQueueAdapter",
      },
      queue_adapters,
    )
  end

  def test_respect_administrator_setting
    if File.exist?(ADDITIONAL_ENVIRONMENT_PATH)
      omit("#{ADDITIONAL_ENVIRONMENT_PATH} already exists")
    end

    begin
      File.write(ADDITIONAL_ENVIRONMENT_PATH, <<~RUBY)
        config.active_job.queue_adapter = :async
      RUBY
      assert_equal(
        {
          "queue_adapter_name" => "async",
          "mailer_queue_adapter" => "ActiveJob::QueueAdapters::AsyncAdapter",
        },
        queue_adapters,
      )
    ensure
      FileUtils.rm_f(ADDITIONAL_ENVIRONMENT_PATH)
    end
  end

  private

  def queue_adapters
    return rails_runner(<<~RUBY)
      {
        "queue_adapter_name" => ActiveJob::Base.queue_adapter_name,
        "mailer_queue_adapter" => ActionMailer::MailDeliveryJob.queue_adapter.class.name,
      }
    RUBY
  end
end
