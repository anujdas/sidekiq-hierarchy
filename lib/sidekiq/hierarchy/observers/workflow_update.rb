module Sidekiq
  module Hierarchy
    module Observers
      class WorkflowUpdate
        def register(callback_registry)
          callback_registry.subscribe(Notifications::WORKFLOW_UPDATE, self)
        end

        def call(root_jid, status, old_status)
          workflow = Workflow.find_by_jid(root_jid)
          from_set = WorkflowSet.for_status(old_status)
          to_set = WorkflowSet.for_status(status)

          # if workflow status is unknown, then... ?
          from_set.delete(workflow) if from_set
          to_set.add(workflow) if to_set
        end
      end
    end
  end
end
