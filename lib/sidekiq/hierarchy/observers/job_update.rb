module Sidekiq
  module Hierarchy
    module Observers
      class JobUpdate
        def register(callback_registry)
          callback_registry.subscribe(Notifications::JOB_UPDATE, self)
        end

        def call(job, status, old_status)
          job.workflow.update_status(status)
        end
      end
    end
  end
end
