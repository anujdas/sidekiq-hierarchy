class NullMiddleware
  def call(*args)
    nil
  end
end

RSpec.shared_context 'with null middleware' do
  before do
    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.add NullMiddleware
      end
    end
  end

  after do
    Sidekiq.configure_client do |config|
      config.client_middleware do |chain|
        chain.remove NullMiddleware
      end
    end
  end
end
