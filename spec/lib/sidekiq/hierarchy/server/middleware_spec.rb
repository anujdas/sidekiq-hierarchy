require 'spec_helper'

class Sidekiq::Shutdown < Interrupt; end

describe Sidekiq::Hierarchy::Server::Middleware do
  after do  # eliminate side-effects
    Sidekiq::Hierarchy.current_workflow = nil
    Sidekiq::Hierarchy.current_jid = nil
  end

  describe '#call' do
    context 'on a job not marked as part of a workflow' do
      context 'with workflow tracking enabled' do
        it 'marks the job as the start of a new workflow' do
          job_id = TestWorker.perform_async
          TestWorker.drain
          expect(Sidekiq::Hierarchy.current_workflow.jid).to eq job_id
        end
      end

      context 'with workflow tracking disabled' do
        it 'does nothing' do
          job_id = UntrackedWorker.perform_async
          UntrackedWorker.drain
          expect(Sidekiq::Hierarchy.current_workflow).to be_nil
        end
      end
    end

    context 'on a job within a workflow' do
      let(:root_jid) { '0123456789ab' }
      let(:root_job) { Sidekiq::Hierarchy::Job.find(root_jid) }
      let(:workflow) { Sidekiq::Hierarchy::Workflow.find(root_job) }
      before { Sidekiq::Hierarchy.current_workflow = workflow }
      it 'saves the workflow root jid' do
        job_id = TestWorker.perform_async
        TestWorker.drain

        expect(Sidekiq::Hierarchy.current_workflow.jid).to_not eq job_id
        expect(Sidekiq::Hierarchy.current_workflow.jid).to eq root_jid
        expect(Sidekiq::Hierarchy.current_workflow).to eq workflow
      end
    end

    context 'on job start' do
      it 'updates workflow status on the current job' do
        job_id = TestWorker.perform_async
        expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_enqueued
      end
    end

    context 'on successful job completion' do
      it 'marks the job as completed' do
        job_id = TestWorker.perform_async
        TestWorker.drain  # perform queued jobs

        expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_complete
      end
    end

    context 'on job failure' do
      context 'of a non-retryable job' do
        it 'marks the job as failed' do
          job_id = FailingWorker.perform_async(StandardError.name)
          expect { FailingWorker.drain }.to raise_error(StandardError)

          expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_failed
        end
      end

      context 'of a retryable job' do
        context 'with retries remaining' do
          it 'marks the job as requeued' do
            job_id = RetryableWorker.perform_async(StandardError.name)
            expect { RetryableWorker.drain }.to raise_error(StandardError)

            expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_requeued
          end
        end

        context 'with no more retries remaining' do
          let(:retry_threshold) { Time.now + 60*60 }  # 1 hour later
          it 'marks the job as failed' do
            job_id = RetryableWorker.perform_async(StandardError.name)

            # first attempt; will place job on retry queue
            expect { RetryableWorker.drain }.to raise_error(StandardError)
            expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_requeued

            # enqueue retried jobs scheduled to execute before retry_threshold
            Sidekiq::Scheduled::Enq.new.enqueue_jobs(retry_threshold.to_f.to_s, ['retry'])

            # second attempt; since RetryableWorker permits one retry, will mark job as dead
            expect { RetryableWorker.drain }.to raise_error(StandardError)
            expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_failed
          end
        end
      end

      context 'due to shutdown' do
        it 'marks the job as requeued' do
          job_id = FailingWorker.perform_async(Sidekiq::Shutdown.name)
          expect { FailingWorker.drain }.to raise_error(Sidekiq::Shutdown)

          expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_requeued
        end
      end
    end
  end
end
