module Sidekiq
  module Hierarchy

    ### Implementations

    # A sorted set of Workflows that permits enumeration
    class WorkflowSet
      PAGE_SIZE = 100

      def self.for_status(status)
        case status
        when :running
          RunningSet.new
        when :complete
          CompleteSet.new
        when :failed
          FailedSet.new
        end
      end

      def initialize(status)
        raise ArgumentError, 'status cannot be nil' if status.nil?
        @status = status
      end

      def ==(other_workflow_set)
        other_workflow_set.instance_of?(self.class)
      end

      def size
        Sidekiq.redis { |conn| conn.zcard(redis_zkey) }
      end

      def add(workflow)
        Sidekiq.redis { |conn| conn.zadd(redis_zkey, Time.now.to_f, workflow.jid) }
      end

      def contains?(workflow)
        !!Sidekiq.redis { |conn| conn.zscore(redis_zkey, workflow.jid) }
      end

      # Remove a workflow from the set if it is present. This operation can
      # only be executed as cleanup (i.e., on a workflow that has been
      # unpersisted/deleted); otherwise it will fail in order to avoid
      # memory leaks.
      def remove(workflow)
        raise 'Workflow still exists' if workflow.exists?
        Sidekiq.redis { |conn| conn.zrem(redis_zkey, workflow.jid) }
      end

      # Move a workflow to this set from its current one
      # This should really be done in Lua, but unit testing support is just not there,
      # so there is a potential race condition in which a workflow could end up in
      # multiple sets. the effect of this is minimal, so we'll fix it later.
      def move(workflow, from_set=nil)
        Sidekiq.redis do |conn|
          conn.multi do
            conn.zrem(from_set.redis_zkey, workflow.jid) if from_set
            conn.zadd(redis_zkey, Time.now.to_f, workflow.jid)
          end.last
        end
      end

      def each
        return enum_for(:each) unless block_given?

        elements = []
        last_max_score = Time.now.to_f
        loop do
          elements = Sidekiq.redis do |conn|
            conn.zrevrangebyscore(redis_zkey, last_max_score, '-inf', limit: [0, PAGE_SIZE], with_scores: true)
              .drop_while { |elt| elements.include?(elt) }
          end
          break if elements.empty?
          elements.each { |jid, _| yield Workflow.find_by_jid(jid) }
          _, last_max_score = elements.last  # timestamp of last element
        end
      end

      def redis_zkey
        "hierarchy:set:#{@status}"
      end
    end

    # An implementation of WorkflowSet that auto-prunes by time & size
    # to stay within space constraints. Do _not_ use for workflows that
    # cannot be lost (i.e., are in any state of progress, or require followup)
    class PruningSet < WorkflowSet
      def self.timeout
        Sidekiq.options[:dead_timeout_in_seconds]
      end

      def self.max_workflows
        Sidekiq.options[:dead_max_workflows] || Sidekiq.options[:dead_max_jobs]
      end

      def add(workflow)
        prune
        super
      end

      def prune
        Sidekiq.redis do |conn|
          conn.multi do
            conn.zrangebyscore(redis_zkey, '-inf', Time.now.to_f - self.class.timeout)  # old workflows
            conn.zrevrange(redis_zkey, self.class.max_workflows, -1)  # excess workflows
          end.flatten.uniq  # take the union of both pruning strategies
            .tap { |to_remove| conn.zrem(redis_zkey, to_remove) if to_remove.any? }
        end.each { |jid| Workflow.find_by_jid(jid).delete }
      end
    end


    ### Instances

    class RunningSet < WorkflowSet
      def initialize
        super 'running'
      end
    end

    class CompleteSet < PruningSet
      def initialize
        super 'complete'
      end
    end

    class FailedSet < PruningSet
      def initialize
        super 'failed'
      end
    end
  end
end
