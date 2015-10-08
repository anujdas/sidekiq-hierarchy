class FailingWorker
  include Sidekiq::Worker
  sidekiq_options retry: false, workflow: true
  def perform(exception_klass)
    raise exception_klass.constantize
  end
end
