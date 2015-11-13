# use fakeredis instead of real redis
# this isn't necessary, but without it, we risk clobbering actual stuff in redis

Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://redis.example.com:6379', driver: Redis::Connection::Memory }
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://redis.example.com:6379', driver: Redis::Connection::Memory }
end
