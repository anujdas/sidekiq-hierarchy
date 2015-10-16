require 'sidekiq'
require 'sidekiq/hierarchy/version'
require 'sidekiq/hierarchy/job'
require 'sidekiq/hierarchy/workflow'
require 'sidekiq/hierarchy/workflow_set'
require 'sidekiq/hierarchy/callback_registry'
require 'sidekiq/hierarchy/notifications'
require 'sidekiq/hierarchy/server/middleware'
require 'sidekiq/hierarchy/client/middleware'

module Sidekiq
  module Hierarchy
    class << self

      ### Per-thread context tracking

      # Checks if tracking is enabled based on whether the workflow is known
      # If disabled, all methods are no-ops
      def enabled?
        !!current_workflow  # without a workflow, we can't do anything
      end

      # Sets the workflow object for the current fiber/worker
      def current_workflow=(workflow)
        Thread.current[:workflow] = workflow
      end

      # Retrieves the current Sidekiq workflow if previously set
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


      ### Workflow execution updates

      def record_job_enqueued(job, redis_pool=nil)
        return unless !!job['workflow']
        if current_jid.nil?
          # this is a root-level job, i.e., start of a workflow
          Sidekiq::Hierarchy::Job.create(job['jid'], job, redis_pool)
        elsif current_jid == job['jid']
          # this is a job requeuing itself, ignore it
        else
          # this is an intermediate job, having both parent and children
          current_job = Sidekiq::Hierarchy::Job.find(current_jid, redis_pool)
          child_job = Sidekiq::Hierarchy::Job.create(job['jid'], job, redis_pool)
          current_job.add_child(child_job)
        end
      end

      def record_job_running
        return unless enabled? && current_jid
        Sidekiq::Hierarchy::Job.find(current_jid).run!
      end

      def record_job_complete
        return unless enabled? && current_jid
        Sidekiq::Hierarchy::Job.find(current_jid).complete!
      end

      def record_job_requeued
        return unless enabled? && current_jid
        Sidekiq::Hierarchy::Job.find(current_jid).requeue!
      end

      def record_job_failed
        return unless enabled? && current_jid
        Sidekiq::Hierarchy::Job.find(current_jid).fail!
      end


      ### Callbacks

      attr_accessor :callback_registry

      def subscribe(event, callback)
        @callback_registry.subscribe(event, callback)
      end

      def publish(event, *args)
        @callback_registry.publish(event, *args)
      end
    end

    self.callback_registry = CallbackRegistry.new
  end
end
