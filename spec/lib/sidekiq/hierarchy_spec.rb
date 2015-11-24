require 'spec_helper'

describe Sidekiq::Hierarchy do
  before(:each) do
    Thread.current[:workflow] = nil
    Thread.current[:jid] = nil
  end

  let(:jid) { '0123456789ab' }
  let(:child_jid) { '02468ace0246' }
  let(:job) { Sidekiq::Hierarchy::Job.find(jid) }
  let(:workflow) { Sidekiq::Hierarchy::Workflow.find(job) }

  describe '.redis=' do
    let(:redis_pool) { ConnectionPool.new { Redis.new } }
    it 'sets the global redis connection' do
      described_class.redis = redis_pool
      expect(Sidekiq::Hierarchy::RedisConnection.redis).to be redis_pool
    end
  end

  describe '.enabled?' do
    it 'checks whether the workflow is known' do
      expect(described_class).to_not be_enabled
      Thread.current[:workflow] = jid
      expect(described_class).to be_enabled
    end
  end

  describe '.current_workflow=' do
    it 'sets the thread-local workflow' do
      expect(Thread.current[:workflow]).to be_nil
      described_class.current_workflow = workflow
      expect(described_class.current_workflow).to eq workflow
    end
  end

  describe '.current_workflow' do
    it 'fetches the thread-local workflow' do
      Thread.current[:workflow] = workflow
      expect(described_class.current_workflow).to eq workflow
    end
    it 'returns nil if thread workflow jid is not set' do
      expect(described_class.current_workflow).to be_nil
    end
  end

  describe '.current_jid=' do
    it 'sets the thread-local jid' do
      expect(Thread.current[:jid]).to be_nil
      described_class.current_jid = jid
      expect(described_class.current_jid).to eq jid
    end
  end

  describe '.current_jid' do
    it 'fetches the thread-local jid' do
      Thread.current[:jid] = jid
      expect(described_class.current_jid).to eq jid
    end
    it 'returns nil if thread jid is not set' do
      expect(described_class.current_jid).to be_nil
    end
  end

  describe '.record_job_enqueued' do
    let(:child_job) { Sidekiq::Hierarchy::Job.find(child_jid) }

    context 'from a non-sidekiq job (Rails action)' do
      context 'within an untracked hierarchy' do
        let(:sidekiq_job) { {'jid' => child_jid, 'workflow' => false} }
        it 'does nothing' do
          described_class.record_job_enqueued(sidekiq_job)
          expect(child_job.exists?).to be_falsey
        end
      end

      context 'with workflow tracking enabled' do
        context 'with the current jid set by middleware' do
          let(:sidekiq_job) { {'jid' => child_jid, 'workflow' => jid} }
          before { described_class.current_jid = jid }
          it 'creates a new child Job and links it to the current jid' do
            expect { described_class.record_job_enqueued(sidekiq_job) }.
              to change { Sidekiq::Hierarchy::Job.find(jid).children }.
              from( [] ).
              to( [child_job] )
            expect(child_job.exists?).to be_truthy
            expect(child_job).to be_enqueued
          end
        end

        context 'without the current jid set' do
          let(:sidekiq_job) { {'jid' => child_jid, 'workflow' => true} }
          it 'creates a new Job' do
            expect { described_class.record_job_enqueued(sidekiq_job) }.
              to change { child_job.exists? }.
              from(false).
              to(true)
            expect(child_job.exists?).to be_truthy
            expect(child_job).to be_enqueued
          end
        end
      end
    end

    context 'from within a sidekiq job' do
      context 'with workflow tracking disabled' do
        let(:sidekiq_job) { {'jid' => child_jid} }
        before { described_class.current_jid = jid }
        it 'does nothing' do
          described_class.record_job_enqueued(sidekiq_job)
          expect(child_job.exists?).to be_falsey
        end
      end

      context 'with workflow tracking enabled' do
        let(:sidekiq_job) { {'jid' => child_jid, 'workflow' => jid} }
        before { described_class.current_jid = jid }
        it 'creates a new child Job and links it to the current jid' do
          expect { described_class.record_job_enqueued(sidekiq_job) }.
            to change { Sidekiq::Hierarchy::Job.find(jid).children }.
            from( [] ).
            to( [child_job] )
          expect(child_job.exists?).to be_truthy
          expect(child_job).to be_enqueued
        end
      end
    end
  end

  describe '.record_job_running' do
    before { described_class.current_jid = jid }
    context 'with workflow tracking disabled' do
      it 'does nothing' do
        described_class.record_job_running
        expect(Sidekiq::Hierarchy::Job.find(jid)).to_not be_running
      end
    end
    context 'with workflow tracking enabled' do
      before { described_class.current_workflow = jid }
      it 'sets the status for the current job to running' do
        described_class.record_job_running
        expect(Sidekiq::Hierarchy::Job.find(jid)).to be_running
      end
    end
  end

  describe '.record_job_complete' do
    before { described_class.current_jid = jid }
    context 'with workflow tracking disabled' do
      it 'does nothing' do
        described_class.record_job_complete
        expect(Sidekiq::Hierarchy::Job.find(jid)).to_not be_complete
      end
    end
    context 'with workflow tracking enabled' do
      before { described_class.current_workflow = jid }
      it 'sets the status for the current job to complete' do
        described_class.record_job_complete
        expect(Sidekiq::Hierarchy::Job.find(jid)).to be_complete
      end
    end
  end

  describe '.record_job_requeued' do
    before { described_class.current_jid = jid }
    context 'with workflow tracking disabled' do
      it 'does nothing' do
        described_class.record_job_requeued
        expect(Sidekiq::Hierarchy::Job.find(jid)).to_not be_requeued
      end
    end
    context 'with workflow tracking enabled' do
      before { described_class.current_workflow = jid }
      it 'sets the status for the current job to requeued' do
        described_class.record_job_requeued
        expect(Sidekiq::Hierarchy::Job.find(jid)).to be_requeued
      end
    end
  end

  describe '.record_job_failed' do
    before { described_class.current_jid = jid }
    context 'with workflow tracking disabled' do
      it 'does nothing' do
        described_class.record_job_failed
        expect(Sidekiq::Hierarchy::Job.find(jid)).to_not be_failed
      end
    end
    context 'with workflow tracking enabled' do
      before { described_class.current_workflow = jid }
      it 'sets the status for the current job to failed' do
        described_class.record_job_failed
        expect(Sidekiq::Hierarchy::Job.find(jid)).to be_failed
      end
    end
  end

  describe '.subscribe' do
    let(:event) { :event }
    let(:callback) { ->(){} }
    it 'adds the callback to the registry' do
      expect(described_class.callback_registry).to receive(:subscribe).with(event, callback)
      described_class.subscribe(event, callback)
    end
  end

  describe '.publish' do
    let(:event) { :event }
    let(:args) { [1,2,3] }
    it 'broadcasts the event to the registry' do
      expect(described_class.callback_registry).to receive(:publish).with(event, *args)
      described_class.publish(event, *args)
    end
  end
end
