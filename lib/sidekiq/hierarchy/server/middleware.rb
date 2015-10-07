module Sidekiq
  module Hierarchy
    module Server
      class Middleware
        def initialize(options={})
        end

        # Wraps around the actual execution of a job. Takes params:
        #   worker - the instance of the worker to be used for execution
        #   msg - the hash of job info, something like {'class' => 'HardWorker', 'args' => [1, 2, 'foo'], 'retry' => true}
        #   queue - the named queue to use
        # Must propagate return value upwards.
        # Since jobs raise errors for signalling, those must be propagated as well.
        def call(worker, msg, queue)
          Sidekiq::Hierarchy.current_jid = worker.jid
          Sidekiq::Hierarchy.record_job_running
          ret = yield
          Sidekiq::Hierarchy.record_job_complete

          ret
        rescue Exception => e
          if msg['retry'] || exception_caused_by_shutdown?(e)
            # job will be pushed back onto queue during hard_shutdown or if retries are permitted
            # for 'dead' jobs (retry exceeded), we'll need to check the DeadSet manually
            Sidekiq::Hierarchy.record_job_requeued
          end

          raise
        end

        def exception_caused_by_shutdown?(e)
          e.instance_of?(Sidekiq::Shutdown) ||
            # In Ruby 2.1+, check if original exception was Shutdown
            (defined?(e.cause) && exception_caused_by_shutdown?(e.cause))
        end
        private :exception_caused_by_shutdown?
      end
    end
  end
end
