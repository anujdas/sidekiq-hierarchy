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
      end

      delegate [:jid, :[], :[]=] => :@root

      def delete
        if workflow_set = WorkflowSet.for_status(status)
          workflow_set.delete(self)
        end
        root.delete
      end

      def ==(other_workflow)
        self.jid == other_workflow.jid
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
        return if [:failed, :complete].include?(old_status)

        if [:enqueued, :running, :requeued].include?(from_job_status)
          new_status, s_val = :running, Job::STATUS_RUNNING
        elsif from_job_status == :failed
          new_status, s_val = :failed, Job::STATUS_FAILED
        elsif from_job_status == :complete && jobs.all?(&:complete?)
          new_status, s_val = :complete, Job::STATUS_COMPLETE
        end

        return if !new_status || new_status == old_status
        self[Job::WORKFLOW_STATUS_FIELD] = s_val

        Sidekiq::Hierarchy.publish(Notifications::WORKFLOW_UPDATE, jid, new_status, old_status)
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
        jobs.max_by { |j| j.complete_at || return }.complete_at
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
