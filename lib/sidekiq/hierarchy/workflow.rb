module Sidekiq
  module Hierarchy
    class Workflow
      extend Forwardable

      attr_reader :root

      def initialize(root)
        @root = root
      end

      class << self
        alias_method :find, :new

        def find_by_jid(root_jid)
          find(Job.find(root_jid))
        end
      end

      delegate [:jid, :[], :[]=, :exists?] => :@root

      def ==(other_workflow)
        other_workflow.instance_of?(self.class) &&
          self.jid == other_workflow.jid
      end

      def workflow_set
        WorkflowSet.for_status(status)
      end

      def delete
        wset = workflow_set  # save it for later
        root.delete  # deleting nodes is more important than a dangling reference
        wset.remove(self) if wset  # now we can clear out from the set
      end

      # Walks the tree in DFS order (for optimal completion checking)
      # Returns an Enumerator; use #to_a to get an array instead
      def jobs
        to_visit = [root]
        Enumerator.new do |y|
          while node = to_visit.pop
            y << node  # sugar for yielding a value
            to_visit += node.children
          end
        end
      end


      ### Status

      def status
        case self[Job::WORKFLOW_STATUS_FIELD]
        when Job::STATUS_RUNNING
          :running
        when Job::STATUS_COMPLETE
          :complete
        when Job::STATUS_FAILED
          :failed
        else
          :unknown
        end
      end

      def update_status(from_job_status)
        old_status = status
        return if [:failed, :complete].include?(old_status)  # these states are final

        if [:enqueued, :running, :requeued].include?(from_job_status)
          new_status, s_val = :running, Job::STATUS_RUNNING
        elsif from_job_status == :failed
          new_status, s_val = :failed, Job::STATUS_FAILED
        elsif from_job_status == :complete && root.subtree_size == root.finished_subtree_size
          new_status, s_val = :complete, Job::STATUS_COMPLETE
        end
        return if !new_status || new_status == old_status  # don't publish null updates

        self[Job::WORKFLOW_STATUS_FIELD] = s_val
        self[Job::WORKFLOW_FINISHED_AT_FIELD] = Time.now.to_f.to_s if [:failed, :complete].include?(new_status)

        Sidekiq::Hierarchy.publish(Notifications::WORKFLOW_UPDATE, self, new_status, old_status)
      end

      def running?
        status == :running
      end

      def complete?
        status == :complete
      end

      def failed?
        status == :failed
      end


      ### Calculated metrics

      def enqueued_at
        root.enqueued_at
      end

      def run_at
        root.run_at
      end

      # Returns the time at which all jobs were complete;
      # nil if any jobs are still incomplete
      def complete_at
        Time.at(self[Job::WORKFLOW_FINISHED_AT_FIELD].to_f) if complete?
      end

      # Returns the earliest time at which a job failed;
      # nil if none did
      def failed_at
        Time.at(self[Job::WORKFLOW_FINISHED_AT_FIELD].to_f) if failed?
      end

      def finished_at
        if timestamp = self[Job::WORKFLOW_FINISHED_AT_FIELD]
          Time.at(timestamp.to_f)
        end
      end


      ### Serialisation

      def as_json(options={})
        root.as_json(options)
      end

      def to_s
        Sidekiq.dump_json(self.as_json)
      end
    end
  end
end
