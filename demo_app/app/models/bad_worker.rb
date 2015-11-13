class BadWorker
  include Sidekiq::Worker

  sidekiq_options retry: false

  def perform(*args)
    raise 'nope'
  end
end
