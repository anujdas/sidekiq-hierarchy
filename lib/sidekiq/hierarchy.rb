require 'sidekiq'
require 'sidekiq/hierarchy/version'
require 'sidekiq/hierarchy/job'
require 'sidekiq/hierarchy/workflow'
require 'sidekiq/hierarchy/server/middleware'
require 'sidekiq/hierarchy/client/middleware'

module Sidekiq
  module Hierarchy
    class << self
      # Sets the workflow root jid for the current fiber/worker
      def current_workflow=(root_jid)
        Thread.current[:workflow] = root_jid
      end

      # Retrieves jid for the current Sidekiq workflow root if previously set
      def current_workflow
        Thread.current[:workflow]
      end

      # Sets the jid for the current fiber/worker
      def current_jid=(jid)
        Thread.current[:jid] = jid
      end

      # Retrieves jid for the current Sidekiq job if previously set
      def current_jid
        Thread.current[:jid]
      end

      def record_job_enqueued(job, redis_pool=nil)
        if current_jid  # this is an intermediate job, having both parent and children
          current_job = Sidekiq::Hierarchy::Job.find(current_jid, redis_pool)
          child_job = Sidekiq::Hierarchy::Job.create(job['jid'], job, redis_pool)
          current_job.add_child(child_job)
        else  # this is a root-level job, i.e., start of a workflow
          Sidekiq::Hierarchy::Job.create(job['jid'], job, redis_pool)
        end
      end

      def record_job_running
        # current_jid should always be set in this context, but...
        Sidekiq::Hierarchy::Job.find(current_jid).run! if current_jid
      end

      def record_job_complete
        # current_jid should always be set in this context, but...
        Sidekiq::Hierarchy::Job.find(current_jid).complete! if current_jid
      end

      def record_job_requeued
        # current_jid should always be set in this context, but...
        Sidekiq::Hierarchy::Job.find(current_jid).requeue! if current_jid
      end

      def record_job_failed
        # current_jid should always be set in this context, but...
        Sidekiq::Hierarchy::Job.find(current_jid).fail! if current_jid
      end
    end
  end
end
