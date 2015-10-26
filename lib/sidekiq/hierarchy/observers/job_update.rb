module Sidekiq
  module Hierarchy
    module Observers
      class JobUpdate
        def register(callback_registry)
          callback_registry.subscribe(Notifications::JOB_UPDATE, self)
        end

        def call(job_jid, status, old_status)
          Job.find(job_jid).workflow.update_status(status)
        end
      end
    end
  end
end
