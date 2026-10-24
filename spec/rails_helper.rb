# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
abort "Specs require RAILS_ENV=test" unless ENV["RAILS_ENV"] == "test"

require_relative "../config/environment"
require "spec_helper"
require "rspec/rails"

# Guard before Rails can prepare or reload a schema. Spec runs must never use
# a development or production database, even with an accidental DATABASE_URL.
unless ActiveRecord::Base.connection_db_config.database.to_s.match?(/(?:\A|[_-])test(?:[_-]|\z)/i)
  abort "Specs require a dedicated database with a 'test' name segment"
end
ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.include ActiveSupport::Testing::TimeHelpers
  config.include ActiveJob::TestHelper
  config.filter_rails_from_backtrace!

  config.before do
    Current.reset
    I18n.locale = I18n.default_locale
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  config.after do
    Current.reset
    I18n.locale = I18n.default_locale
  end
end
