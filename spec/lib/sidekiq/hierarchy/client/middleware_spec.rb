require 'spec_helper'

describe Sidekiq::Hierarchy::Client::Middleware do
  let(:parent_jid) { '0123456789ab' }
  let(:parent_job) { Sidekiq::Hierarchy::Job.create(parent_jid, {}) }

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

        context 'with workflow tracking disabled on the child job' do
          it 'does not track the job' do
            job_id = UntrackedWorker.perform_async
            expect(Sidekiq::Hierarchy::Job.find(job_id).exists?).to be_falsey
          end
        end
      end

      context 'within a workflow' do
        before { Sidekiq::Hierarchy.current_workflow = Sidekiq::Hierarchy::Workflow.find(parent_job) }
        after  { Sidekiq::Hierarchy.current_workflow = nil }

        it 'passes the workflow jid to the new job' do
          TestWorker.perform_async
          expect(TestWorker.jobs.first['workflow']).to eq parent_jid
        end

        context 'with workflow tracking disabled on the child job' do
          it 'tracks the job anyway' do
            UntrackedWorker.perform_async
            expect(UntrackedWorker.jobs.first['workflow']).to eq parent_jid
          end
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

    context 'on a sidekiq version without redis_pool' do
      let(:jid) { 1 }
      it 'functions correctly with the default redis' do
        expect{ subject.call(TestWorker.class, {}, '') { {'workflow' => true, 'jid' => jid} } }.to_not raise_error
        expect(Sidekiq::Hierarchy::Job.find(jid)).to be_enqueued
      end
    end
  end
end
