#!/usr/bin/env ruby

# Run in Redmine's root directory:
#
#   $ bundle exec ruby plugins/redmine_solid_queue/test/run-test.rb

require "test-unit"

exit(Test::Unit::AutoRunner.run(true, __dir__))
