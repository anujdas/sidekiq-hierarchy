Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379/1' }

  config.client_middleware do |chain|
    chain.add Sidekiq::Hierarchy::Client::Middleware
  end
end

Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://localhost:6379/1' }

  config.client_middleware do |chain|
    chain.add Sidekiq::Hierarchy::Client::Middleware
  end

  config.server_middleware do |chain|
    chain.add Sidekiq::Hierarchy::Server::Middleware
  end
end
