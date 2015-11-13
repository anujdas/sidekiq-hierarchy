class FailingWorker
  include Sidekiq::Worker

  def perform(*args)
    raise 'nope' unless rand(2) == 1
  end
end
