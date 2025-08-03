# frozen_string_literal: true

require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.ignore_localhost = true
  config.configure_rspec_metadata!

  # Allow real HTTP connections when no cassette is in use
  config.allow_http_connections_when_no_cassette = true

  # Filter sensitive data
  config.filter_sensitive_data("<GITHUB_TOKEN>") { ENV["GITHUB_TOKEN"] }
  config.filter_sensitive_data("<GITHUB_TOKEN>") { Rails.application.credentials.github.api_token }

  # Default cassette options
  config.default_cassette_options = {
    record: :new_episodes, # Allow recording new API calls
    match_requests_on: [:method, :uri, :body],
    allow_unused_http_interactions: false,
    # Decode compressed responses for readability
    decode_compressed_response: true,
    # Serialize with pretty formatting
    serialize_with: :yaml,
    preserve_exact_body_bytes: false
  }

  # Only preserve exact body bytes for actual binary content
  config.preserve_exact_body_bytes do |http_message|
    # Only preserve binary for non-JSON responses
    content_type = http_message.headers["Content-Type"]&.first
    content_type && !content_type.include?("json")
  end
end
