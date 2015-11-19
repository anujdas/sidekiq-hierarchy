module Sidekiq
  module Hierarchy
    module Client
      class Middleware
        def initialize(options={})
        end

        # Wraps around the method used to push a job to Redis. Takes params:
        #   worker_class - the class of the worker, as an object
        #   msg - the hash of job info, something like {'class' => 'HardWorker', 'args' => [1, 2, 'foo'], 'retry' => true}
        #   queue - the named queue to use
        #   redis_pool - a redis-like connection/conn-pool
        # Must propagate return value upwards.
        # May return false/nil to stop the job from going to redis.
        def call(worker_class, msg, queue, redis_pool=nil)
          msg['workflow'] = Sidekiq::Hierarchy.current_workflow.jid if Sidekiq::Hierarchy.current_workflow
          # if block returns nil/false, job was cancelled before queueing by middleware
          yield.tap { |job| Sidekiq::Hierarchy.record_job_enqueued(job, redis_pool) if job }
        end
      end
    end
  end
end
