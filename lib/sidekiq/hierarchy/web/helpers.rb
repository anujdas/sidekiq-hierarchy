module Sidekiq
  module Hierarchy
    module Web
      module Helpers
        # Override find_template logic to process arrays of view directories
        # warning: this may be incompatible with other overrides of find_template,
        # though that really shouldn't happen if they match the method contract
        def find_template(views, name, engine, &block)
          Array(views).each do |view_dir|
            super(view_dir, name, engine, &block)
          end
        end

        def job_url(job=nil)
          "#{root_path}hierarchy/jobs/#{job.jid if job}"
        end

        def workflow_url(workflow=nil)
          "#{root_path}hierarchy/workflows/#{workflow.jid if workflow}"
        end

        def workflow_set_url(status)
          "#{root_path}hierarchy/workflow_sets/#{status}"
        end

        def safe_relative_time(timestamp)
          timestamp.nil? ? '-' : relative_time(timestamp)
        end

        def status_updated_at(job)
          case job.status
          when :enqueued
            job.enqueued_at
          when :running, :requeued
            job.run_at
          when :complete
            job.complete_at
          when :failed
            job.failed_at
          end
        end

        def bootstrap_status(status)
          case status
          when :enqueued, :requeued
            'warning'
          when :running
            'info'
          when :complete
            'success'
          when :failed
            'danger'
          end
        end
      end
    end
  end
end
