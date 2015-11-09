module Sidekiq
  module Hierarchy
    module Observers
      class WorkflowUpdate
        def register(callback_registry)
          callback_registry.subscribe(Notifications::WORKFLOW_UPDATE, self)
        end

        def call(root_jid, status, old_status)
          workflow = Workflow.find_by_jid(root_jid)
          to_set = WorkflowSet.for_status(status)
          to_set.move(workflow)  # Move/add to the new status set
        end
      end
    end
  end
end
