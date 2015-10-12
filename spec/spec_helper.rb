$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'rspec'
require 'rspec/its'

require 'fakeredis/rspec'
require 'rspec-sidekiq'

require 'sidekiq-hierarchy'

Dir[File.dirname(__FILE__) + '/support/**/*.rb'].each { |f| require f }

RSpec.configure do |config|
  config.before(:each) do
    Sidekiq.redis { |conn| conn.flushdb }  # clear out redis between specs
  end
end
