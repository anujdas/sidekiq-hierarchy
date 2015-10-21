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

      delegate [:jid, :[], :[]=, :delete] => :@root

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

      def update_status(job_status)
        if [:enqueued, :running, :requeued].include?(job_status)
          self[Job::WORKFLOW_STATUS_FIELD] = Job::STATUS_RUNNING
        elsif job_status == :failed
          self[Job::WORKFLOW_STATUS_FIELD] = Job::STATUS_FAILED
        elsif job_status == :complete && jobs.all?(&:complete?)
          self[Job::WORKFLOW_STATUS_FIELD] = Job::STATUS_COMPLETE
        end
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
