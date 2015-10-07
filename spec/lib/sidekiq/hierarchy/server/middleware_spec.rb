require 'spec_helper'

class Sidekiq::Shutdown < Interrupt; end

describe Sidekiq::Hierarchy::Server::Middleware do
  describe '#call' do
    context 'on job start' do
      let(:job) { double('Sidekiq::Hierarchy::Job', enqueue!: nil, run!: nil, complete!: nil) }
      before do
        allow(Sidekiq::Hierarchy::Job).to receive(:find).and_return(job)
      end
      it 'updates workflow status on the current job' do
        job_id = TestWorker.perform_async
        Sidekiq::Worker.drain_all  # perform queued jobs

        expect(Sidekiq::Hierarchy::Job).to have_received(:find).with(job_id).at_least(1)
        expect(job).to have_received(:run!).once
      end
    end

    context 'on successful job completion' do
      it 'marks the job as completed' do
        job_id = TestWorker.perform_async
        Sidekiq::Worker.drain_all  # perform queued jobs

        expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_complete
      end
    end

    context 'on job failure' do
      context 'of a non-retryable job' do
        xit 'marks the job as failed' do
        end
      end

      context 'of a retryable job' do
        context 'with retries remaining' do
          it 'marks the job as requeued' do
            job_id = RetryableWorker.perform_async(StandardError.name)
            begin
              Sidekiq::Worker.drain_all  # perform queued jobs
            rescue => e  # middleware will re-raise exception
            end

            expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_requeued
          end
        end
        context 'with no more retries remaining' do
          xit 'marks the job as failed' do
          end
        end
      end

      context 'due to shutdown' do
        it 'marks the job as requeued' do
          job_id = FailingWorker.perform_async(Sidekiq::Shutdown.name)
          begin
            Sidekiq::Worker.drain_all  # perform queued jobs
          rescue Sidekiq::Shutdown  # middleware will re-raise exception
          end

          expect(Sidekiq::Hierarchy::Job.find(job_id)).to be_requeued
        end
      end
    end
  end
end
