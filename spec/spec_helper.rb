$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'fakeredis/rspec'
require 'sidekiq-hierarchy'

RSpec.configure do |config|
  config.before(:each) do
    Sidekiq.redis { |conn| conn.flushdb }  # clear out redis between specs
  end
end
