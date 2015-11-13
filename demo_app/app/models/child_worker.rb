class ChildWorker
  include Sidekiq::Worker

  def perform(*args)
    if rand(2) == 0
      TestWorker.perform_async(*args)
    else
      BadWorker.perform_async(*args)
    end
  end
end
