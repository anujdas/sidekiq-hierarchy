module Sidekiq
  module Hierarchy
    class Workflow
      attr_reader :root

      def initialize(root_jid, redis_pool=nil)
        @root = Sidekiq::Hierarchy::Job.new(root_jid, redis_pool)
      end

      # Walks the tree in DFS order (for optimal completion checking)
      # Returns an Enumerator; use #to_a to get an array instead
      def jobs
        to_visit = [@root]
        Enumerator.new do |y|
          while node = to_visit.pop
            y << node  # sugar for yielding a value
            to_visit += node.children
          end
        end
      end

      def running?
        jobs.any? { |job| job.enqueued? || job.requeued? || job.running? }
      end

      def complete?
        jobs.all?(&:complete?)
      end

      def failed?
        jobs.any?(&:failed?)
      end
    end
  end
end
