module Sidekiq
  module Hierarchy
    module RedisConnection
      # A translation class turning a Redis object into a ConnectionPool-alike
      class ConnectionProxy
        attr_reader :redis

        def initialize(redis_conn)
          raise 'connection must be an instance of Redis' unless redis_conn.is_a?(::Redis)
          @redis = redis_conn
        end

        def with(&blk)
          blk.call(redis)
        end
      end

      class << self
        attr_reader :redis

        # Set global redis
        def redis=(conn)
          @redis = if conn.nil?
                     nil
                   elsif conn.is_a?(::ConnectionPool)
                     conn
                   else
                     ConnectionProxy.new(conn)
                   end
        end
      end

      # Use global redis if set, with a fallback to Sidekiq's redis pool
      def redis(&blk)
        if RedisConnection.redis
          RedisConnection.redis.with(&blk)
        else
          Sidekiq.redis(&blk)
        end
      end
    end
  end
end
