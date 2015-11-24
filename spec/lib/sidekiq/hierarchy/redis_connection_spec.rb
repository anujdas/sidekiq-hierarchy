require 'spec_helper'

describe Sidekiq::Hierarchy::RedisConnection do
  before { described_class.redis = nil }

  describe '.redis=' do
    context 'given nothing' do
      before { described_class.redis = Redis.new }
      it 'nulls out the global redis' do
        described_class.redis = nil
        expect(described_class.redis).to be_nil
      end
    end

    context 'given a Redis client connection' do
      let(:redis_conn) { Redis.new }
      it 'wraps the connection in a ConnectionPool-like proxy' do
        described_class.redis = redis_conn
        expect(described_class.redis).to respond_to(:with)

        allow(redis_conn).to receive(:get).with('key').and_return('value')
        expect(described_class.redis.with { |c| c.get('key') }).to eq 'value'
      end
    end

    context 'given a ConnectionPool' do
      let(:redis_pool) { ConnectionPool.new { Redis.new } }
      it 'keeps the pool object as-is' do
        described_class.redis = redis_pool
        expect(described_class.redis).to eq redis_pool
      end
    end
  end

  describe '#redis' do
    class RedisConsumer
      include Sidekiq::Hierarchy::RedisConnection
    end

    subject(:redis_consumer) { RedisConsumer.new }

    context 'without an explicit Redis connection set' do
      let(:block) { Proc.new {|r| r.get('key')} }
      let(:redis) { double('Sidekiq.redis') }
      before { allow(Sidekiq).to receive(:redis).and_yield(redis) }
      it 'delegates to the Sidekiq redis pool' do
        allow(redis).to receive(:get).with('key').and_return('value')
        expect(redis_consumer.redis(&block)).to eq 'value'
      end
    end

    context 'with a separate Redis pool specified' do
      before { described_class.redis = ConnectionPool.new { Redis.new } }
      it 'uses the given pool for all commands' do
        expect { |blk| redis_consumer.redis(&blk) }.to yield_with_args(Redis)
      end
    end
  end
end
