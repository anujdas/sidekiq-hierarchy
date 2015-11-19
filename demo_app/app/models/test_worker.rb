class TestWorker
  include Sidekiq::Worker

  SAMPLE = [0, 0, 1, 5]

  sidekiq_options workflow: true, workflow_keys: ['args']

  def perform(*args)
    sleep 2
    SAMPLE.sample.times do |n|
      TestWorker.perform_async(n)
    end
  end
end
