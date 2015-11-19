# Web interface to Sidekiq-hierarchy
# Optimised for ease-of-use, not efficiency; it's probably best
# not to leave this open in a tab forever.
# Sidekiq seems to use Bootstrap 3.0.0 currently; find docs at
# http://bootstrapdocs.com/v3.0.0/docs/
module Sidekiq
  module Hierarchy
    module Web
      module Helpers
        def sidekiq_hierarchy_template(template_name)
          File.read(File.join(VIEW_PATH, "#{template_name}.erb"))
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

      VIEW_PATH = File.expand_path('../../../../web/views', __FILE__)
      PER_PAGE = 20

      def self.registered(app)
        app.helpers Helpers

        app.not_found do
          erb sidekiq_hierarchy_template(:not_found)
        end

        app.get '/hierarchy/?' do
          @running_set = RunningSet.new
          @complete_set = CompleteSet.new
          @failed_set = FailedSet.new

          @running = @running_set.each.take(PER_PAGE)
          @complete = @complete_set.each.take(PER_PAGE)
          @failed = @failed_set.each.take(PER_PAGE)

          erb sidekiq_hierarchy_template(:status)
        end

        app.delete '/hierarchy/?' do
          [RunningSet.new, CompleteSet.new, FailedSet.new].each(&:remove_all)
          redirect back
        end

        app.get '/hierarchy/workflow_sets/:status' do |status|
          @status = status.to_sym
          if @workflow_set = WorkflowSet.for_status(@status)
            @workflows = @workflow_set.each.take(PER_PAGE)
            erb sidekiq_hierarchy_template(:workflow_set)
          else
            halt 404
          end
        end

        app.delete '/hierarchy/workflow_sets/:status' do |status|
          @status = status.to_sym
          if workflow_set = WorkflowSet.for_status(@status)
            workflow_set.each(&:delete)
            redirect back
          else
            halt 404
          end
        end

        app.get '/hierarchy/workflows/?' do
          if params['workflow_jid'] =~ /\A\h{24}\z/
            redirect to("/hierarchy/workflows/#{params['workflow_jid']}")
          else
            redirect to(:hierarchy)
          end
        end

        app.get %r{\A/hierarchy/workflows/(\h{24})\z} do |workflow_jid|
          @workflow = Workflow.find_by_jid(workflow_jid)
          if @workflow.exists?
            erb sidekiq_hierarchy_template(:workflow)
          else
            halt 404
          end
        end

        app.delete %r{\A/hierarchy/workflows/(\h{24})\z} do |workflow_jid|
          workflow = Workflow.find_by_jid(workflow_jid)
          redirect_url = "/hierarchy/workflow_sets/#{workflow.status}"
          workflow.delete

          redirect to(redirect_url)
        end

        app.get '/hierarchy/jobs/?' do
          if params['jid'] =~ /\A\h{24}\z/
            redirect to("/hierarchy/jobs/#{params['jid']}")
          else
            redirect back
          end
        end

        app.get %r{\A/hierarchy/jobs/(\h{24})\z} do |jid|
          @job = Job.find(jid)
          @workflow = @job.workflow
          if @job.exists? && @workflow.exists?
            erb sidekiq_hierarchy_template(:job)
          else
            halt 404
          end
        end
      end
    end
  end
end

require 'sidekiq/web' unless defined?(Sidekiq::Web)
Sidekiq::Web.register(Sidekiq::Hierarchy::Web)
Sidekiq::Web.tabs['Hierarchy'] = 'hierarchy'
