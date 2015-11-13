class ParentWorker
  include Sidekiq::Worker

  sidekiq_options queue: :high

  def perform(*args)
    5.times do |n|
      TestWorker.perform_async(n)
    end
  end
end
