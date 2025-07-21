gem "solid_queue"

# set queue_adapter :solid_queue as default
trace = TracePoint.new(:end) do |tp|
  next if tp.self.name != "RedmineApp::Application"

  trace.disable

  # respect administrator's setting
  next if tp.self.config.active_job.queue_adapter

  tp.self.config.active_job.queue_adapter = :solid_queue
end
trace.enable

if ENV["REDMINE_SOLID_QUEUE_DISABLE_PUMA_PLUGIN"] != "1"
  # automatically enable :solid_queue Puma plugin
  begin
    require "puma"
    require "puma/configuration"
    Puma::Configuration.prepend(
      Module.new do
        def load
          return super.tap do
            @file_dsl.plugin(:solid_queue)
          end
        end
      end
    )
  rescue LoadError
    # nop
  end
end
