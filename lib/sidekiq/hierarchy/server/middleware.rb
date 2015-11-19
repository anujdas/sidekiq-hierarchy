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
          if msg['workflow'] == true  # root job -- start of a new workflow
            Sidekiq::Hierarchy.current_workflow = Workflow.find_by_jid(worker.jid)
            Sidekiq::Hierarchy.current_jid = worker.jid
          elsif msg['workflow'].is_a?(String)  # child job -- inherit parent's workflow
            Sidekiq::Hierarchy.current_workflow = Workflow.find_by_jid(msg['workflow'])
            Sidekiq::Hierarchy.current_jid = worker.jid
          end

          Sidekiq::Hierarchy.record_job_running
          ret = yield
          Sidekiq::Hierarchy.record_job_complete

          ret
        rescue Exception => e
          if exception_caused_by_shutdown?(e) || retries_remaining?(msg)
            # job will be pushed back onto queue during hard_shutdown or if retries are permitted
            Sidekiq::Hierarchy.record_job_requeued
          else
            Sidekiq::Hierarchy.record_job_failed
          end

          raise
        end

        def retries_remaining?(msg)
          return false unless msg['retry']

          retry_count = msg['retry_count'] || 0
          max_retries = if msg['retry'].is_a?(Fixnum)
                          msg['retry']
                        else
                          Sidekiq::Middleware::Server::RetryJobs::DEFAULT_MAX_RETRY_ATTEMPTS
                        end

          # this check requires prepending the middleware before sidekiq's builtin retry
          retry_count < max_retries
        end
        private :retries_remaining?

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
