require 'spec_helper'

describe Sidekiq::Hierarchy::Client::Middleware do
  let(:parent_jid) { '0123456789ab' }
  let(:parent_job) { Sidekiq::Hierarchy::Job.create(parent_jid) }

  before { parent_job.complete! }

  describe '#call' do
    context 'on job creation' do
      it 'marks the new job as enqueued' do
        job_id = TestWorker.perform_async
        expect(TestWorker).to have_enqueued_job
        expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_enqueued
      end

      context 'from a Sidekiq job' do
        before { Sidekiq::Hierarchy.current_jid = parent_jid }
        after  { Sidekiq::Hierarchy.current_jid = nil }

        it "adds the created job to the current job's children list" do
          job_id = TestWorker.perform_async
          expect(parent_job.children.map(&:jid)).to include job_id
        end

        it "records the current job as its child's parent" do
          job_id = TestWorker.perform_async
          expect(Sidekiq::Hierarchy::Job.find(job_id).parent).to eq parent_job
        end
      end

      context 'within a workflow' do
        before { Sidekiq::Hierarchy.current_workflow = parent_jid }
        after  { Sidekiq::Hierarchy.current_workflow = nil }

        it 'passes the workflow jid to the new job' do
          TestWorker.perform_async
          expect(TestWorker.jobs.first['workflow']).to eq parent_jid
        end
      end
    end

    context 'on job cancellation by a nested middleware' do
      include_context 'with null middleware'

      it 'does nothing' do
        job_id = TestWorker.perform_async
        expect(TestWorker).to_not have_enqueued_job
        expect(Sidekiq::Hierarchy::Job.find(job_id)).to_not exist
      end
    end
  end
end
