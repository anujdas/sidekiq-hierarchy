require 'celluloid'  # required for retry_jobs
require 'sidekiq/middleware/server/retry_jobs'

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.prepend Sidekiq::Hierarchy::Client::Middleware
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.prepend Sidekiq::Hierarchy::Server::Middleware
  end
  config.client_middleware do |chain|
    chain.prepend Sidekiq::Hierarchy::Client::Middleware
  end
end

Sidekiq::Testing.server_middleware do |chain|
  chain.prepend Sidekiq::Hierarchy::Server::Middleware
  chain.add Sidekiq::Middleware::Server::RetryJobs
end
