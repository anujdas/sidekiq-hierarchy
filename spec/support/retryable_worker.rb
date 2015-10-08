require_relative 'failing_worker'
class RetryableWorker < FailingWorker
  sidekiq_options retry: 1, workflow: true
end
