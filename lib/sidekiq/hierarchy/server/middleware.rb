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
          yield
        ensure
        end
      end
    end
  end
end
