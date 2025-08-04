# frozen_string_literal: true

Octokit.configure do |c|
  c.auto_paginate = false # We handle pagination manually
  c.per_page = 100

  # Configure Faraday connection with appropriate timeouts for large repositories
  c.connection_options = {
    request: {
      open_timeout: 30,    # Time to establish connection (30 seconds)
      read_timeout: 300,   # Time to read response data (5 minutes)
    }
  }
end
