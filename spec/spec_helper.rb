$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'rspec'
require 'rspec/its'

require 'fakeredis/rspec'
require 'rspec-sidekiq'

require 'sidekiq-hierarchy'

Dir[File.dirname(__FILE__) + '/support/**/*.rb'].each { |f| require f }

RSpec.configure do |config|
  # configuration here
end
