class UntrackedWorker
  include Sidekiq::Worker
  def perform(*args)
    # no-op
  end
end
