require 'spec_helper'

describe Sidekiq::Hierarchy do
  before(:each) do
    Thread.current[:workflow] = nil
    Thread.current[:jid] = nil
  end

  let(:jid) { '0123456789ab' }
  let(:child_jid) { '02468ace0246' }

  describe '.current_workflow=' do
    it 'sets the thread-local workflow jid' do
      expect(Thread.current[:workflow]).to be_nil
      described_class.current_workflow = jid
      expect(described_class.current_workflow).to eq jid
    end
  end

  describe '.current_workflow' do
    it 'fetches the thread-local workflow root jid' do
      Thread.current[:workflow] = jid
      expect(described_class.current_workflow).to eq jid
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
    let(:sidekiq_job) { {'jid' => child_jid} }
    let(:child_job) { Sidekiq::Hierarchy::Job.find(child_jid) }

    context 'from a non-sidekiq job (Rails action)' do
      context 'with the current jid set by middleware' do
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

    context 'from within a sidekiq job' do
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

  describe '.record_job_running' do
    before { described_class.current_jid = jid }
    it 'sets the status for the current job to running' do
      described_class.record_job_running
      expect(Sidekiq::Hierarchy::Job.find(jid)).to be_running
    end
  end

  describe '.record_job_complete' do
    before { described_class.current_jid = jid }
    it 'sets the status for the current job to complete' do
      described_class.record_job_complete
      expect(Sidekiq::Hierarchy::Job.find(jid)).to be_complete
    end
  end

  describe '.record_job_requeued' do
    before { described_class.current_jid = jid }
    it 'sets the status for the current job to requeued' do
      described_class.record_job_requeued
      expect(Sidekiq::Hierarchy::Job.find(jid)).to be_requeued
    end
  end

  describe '.record_job_failed' do
    before { described_class.current_jid = jid }
    it 'sets the status for the current job to failed' do
      described_class.record_job_failed
      expect(Sidekiq::Hierarchy::Job.find(jid)).to be_failed
    end
  end
end
