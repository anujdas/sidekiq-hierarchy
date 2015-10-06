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
