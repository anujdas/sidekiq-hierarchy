module Sidekiq
  module Hierarchy
    module Web
      module Helpers
        TIME_TO_WORD = {
          29030400 => 'year',
          2419200 => 'month',
          604800 => 'week',
          86400 => 'day',
          3600 => 'hour',
          60 => 'minute',
          1 => 'second',
        }


        ### TEMPLATE HELPERS

        # Override find_template logic to process arrays of view directories
        # warning: this may be incompatible with other overrides of find_template,
        # though that really shouldn't happen if they match the method contract
        def find_template(views, name, engine, &block)
          Array(views).each do |view_dir|
            super(view_dir, name, engine, &block)
          end
        end

        ### ROUTE HELPERS

        def job_url(job=nil)
          "#{root_path}hierarchy/jobs/#{job.jid if job}"
        end

        def workflow_url(workflow=nil)
          "#{root_path}hierarchy/workflows/#{workflow.jid if workflow}"
        end

        def workflow_set_url(status)
          "#{root_path}hierarchy/workflow_sets/#{status}"
        end


        ### FORMATTING HELPERS

        def safe_relative_time(timestamp)
          timestamp.nil? ? '-' : relative_time(timestamp)
        end

        def time_in_words(time)
          divisor, period = TIME_TO_WORD.select { |secs, _| time.ceil >= secs }.max_by(&:first)
          duration = (time / divisor).to_i

          "#{duration} #{period}#{'s' unless duration == 1}"
        end


        ### HUMANIZATION HELPERS

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

        def status_in_words(job)
          case job.status
          when :enqueued
            "enqueued #{safe_relative_time(job.enqueued_at)}"
          when :requeued
            "requeued #{safe_relative_time(job.enqueued_at)}"
          when :running
            "running #{time_in_words(Time.now - job.run_at)}"
          when :complete
            "complete in #{time_in_words(job.complete_at - job.run_at)}"
          when :failed
            "failed in #{time_in_words(job.failed_at - job.run_at)}"
          end
        end
      end
    end
  end
end
