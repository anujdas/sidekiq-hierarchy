class FailingWorker
  include Sidekiq::Worker
  def perform(exception_klass)
    raise exception_klass.constantize
  end
end
