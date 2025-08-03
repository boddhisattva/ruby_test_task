# frozen_string_literal: true

require "sidekiq/testing"
require "rspec-sidekiq"

# Configure Sidekiq for test environment
RSpec.configure do |config|
  # Set fake mode globally for ALL tests
  # This ensures jobs are queued but never executed
  config.before(:suite) do
    Sidekiq::Testing.fake!
  end

  # Clear all job queues before each test
  # This prevents job contamination between tests
  config.before do
    Sidekiq::Worker.clear_all
  end

  # Run jobs inline for tests marked with :sidekiq_inline metadata
  config.around do |example|
    if example.metadata[:sidekiq_inline] == true
      Sidekiq::Testing.inline! { example.run }
    else
      example.run
    end
  end

  # Include rspec-sidekiq matchers for better assertions
  config.include RSpec::Sidekiq::Matchers
end
