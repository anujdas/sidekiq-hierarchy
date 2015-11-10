module Sidekiq
  module Hierarchy
    module Observers
      class WorkflowUpdate
        def register(callback_registry)
          callback_registry.subscribe(Notifications::WORKFLOW_UPDATE, self)
        end

        def call(workflow, status, old_status)
          from_set = WorkflowSet.for_status(old_status)
          to_set = WorkflowSet.for_status(status)

          to_set.move(workflow, from_set)  # Move/add to the new status set
        end
      end
    end
  end
end
