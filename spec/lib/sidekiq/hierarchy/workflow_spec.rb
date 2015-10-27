require 'spec_helper'

describe Sidekiq::Hierarchy::Workflow do
  let(:job_info) { {'class' => 'HardWorker', 'args' => [1, 'foo']} }
  let(:root) { Sidekiq::Hierarchy::Job.create('0', job_info) }
  let(:level1) { [Sidekiq::Hierarchy::Job.create('1', job_info), Sidekiq::Hierarchy::Job.create('2', job_info)] }
  let(:level2) { [Sidekiq::Hierarchy::Job.create('3', job_info), Sidekiq::Hierarchy::Job.create('4', job_info)] }

  # construct a workflow tree:
  #             root #0
  #             /    \
  #       level1 #1  level1 #2
  #       /       \
  # level2 #3   level2 #4
  before do
    level1.each { |child| root.add_child(child) }
    level2.each { |child| level1.first.add_child(child) }
  end

  subject(:workflow) { described_class.find(root) }

  describe '.find' do
    let(:existing_workflow) { described_class.find(root) }
    it 'instantiates a Workflow object for the given jid' do
      expect(existing_workflow).to be_a(described_class)
      expect(existing_workflow.root).to eq root
    end
  end

  describe '#jid' do
    it 'returns the root job jid' do
      expect(workflow.jid).to eq workflow.root.jid
    end
  end

  describe '#[]' do
    it 'retrieves attrs from the root job' do
      workflow.root[:attr] = 'value'
      expect(workflow[:attr]).to eq 'value'
    end
  end

  describe '#[]=' do
    it 'sets attrs on the root job' do
      workflow[:attr] = 'value'
      expect(workflow.root[:attr]).to eq 'value'
    end
  end

  describe '#==' do
    let(:copy) { described_class.find(root) }
    let(:noncopy) { described_class.find(level1.first) }
    it 'compares jids' do
      expect(workflow).to eq copy
      expect(workflow).to_not eq noncopy
    end
  end

  describe '#workflow_set' do
    it 'returns the RunningSet for a running workflow' do
      allow(workflow).to receive(:status).and_return(:running)
      expect(workflow.workflow_set).to be_an_instance_of Sidekiq::Hierarchy::RunningSet
    end
    it 'returns the CompleteSet for a complete workflow' do
      allow(workflow).to receive(:status).and_return(:complete)
      expect(workflow.workflow_set).to be_an_instance_of Sidekiq::Hierarchy::CompleteSet
    end
    it 'returns the FailedSet for a failed workflow' do
      allow(workflow).to receive(:status).and_return(:failed)
      expect(workflow.workflow_set).to be_an_instance_of Sidekiq::Hierarchy::FailedSet
    end
  end

  describe '#delete' do
    let(:workflow_set) { double('Sidekiq::Hierarchy::WorkflowSet', delete: nil) }
    before { allow(workflow).to receive(:workflow_set).and_return(workflow_set) }
    it 'deletes the root node' do
      expect(workflow.root).to receive(:delete)
      workflow.delete
    end
    it 'removes the workflow from its status set' do
      expect(workflow_set).to receive(:delete).with(workflow)
      workflow.delete
    end
  end

  describe '#jobs' do
    it 'returns a lazy Enumerator' do
      expect(workflow.jobs).to be_an Enumerator
      expect(workflow.jobs.first.jid).to eq root.jid
      expect(workflow.jobs.count).to eq ([root] + level1 + level2).length
    end
    it 'traverses all nodes depth-first reverse-order' do
      expect(workflow.jobs.map(&:jid)).to eq ['0', '2', '1', '4', '3']
    end
  end

  describe '#status' do
    it 'reflects the current status as a symbol' do
      workflow[Sidekiq::Hierarchy::Job::WORKFLOW_STATUS_FIELD] = Sidekiq::Hierarchy::Job::STATUS_RUNNING
      expect(workflow.status).to eq :running

      workflow[Sidekiq::Hierarchy::Job::WORKFLOW_STATUS_FIELD] = Sidekiq::Hierarchy::Job::STATUS_COMPLETE
      expect(workflow.status).to eq :complete

      workflow[Sidekiq::Hierarchy::Job::WORKFLOW_STATUS_FIELD] = Sidekiq::Hierarchy::Job::STATUS_FAILED
      expect(workflow.status).to eq :failed
    end
    it 'returns unknown if the status does not match a known value' do
      workflow[Sidekiq::Hierarchy::Job::WORKFLOW_STATUS_FIELD] = nil
      expect(workflow.status).to eq :unknown
    end
  end

  describe '#update_status' do
    before do
      (level1 + level2).each(&:complete!)
      root.requeue!
    end

    context 'when a job is enqueued' do
      before { workflow.update_status(:enqueued) }
      it 'sets the status to running' do
        expect(workflow.status).to eq :running
      end
    end

    context 'when a job is running' do
      before { workflow.update_status(:running) }
      it 'sets the status to running' do
        expect(workflow.status).to eq :running
      end
    end

    context 'when a job is requeued' do
      before { workflow.update_status(:requeued) }
      it 'sets the status to running' do
        expect(workflow.status).to eq :running
      end
    end

    context 'when a job fails' do
      before { workflow.update_status(:failed) }
      it 'sets the status to failed' do
        expect(workflow.status).to eq :failed
      end
    end

    context 'when a job completes' do
      context 'and some jobs are still incomplete' do
        it 'does not change the workflow status' do
          expect { workflow.update_status(:complete) }.to_not change { workflow.status }
        end
      end
      context 'and all other jobs are completed' do
        before { root[Sidekiq::Hierarchy::Job::STATUS_FIELD] = Sidekiq::Hierarchy::Job::STATUS_COMPLETE }
        it 'sets the status to failed' do
          workflow.update_status(:complete)
          expect(workflow.status).to eq :complete
        end
      end
    end
  end

  describe '#running?' do
    it 'checks if the status is :running' do
      allow(workflow).to receive(:status).and_return(:complete)
      expect(workflow).to_not be_running

      allow(workflow).to receive(:status).and_return(:running)
      expect(workflow).to be_running
    end
  end

  describe '#complete?' do
    it 'checks if the status is :complete' do
      allow(workflow).to receive(:status).and_return(:running)
      expect(workflow).to_not be_complete

      allow(workflow).to receive(:status).and_return(:complete)
      expect(workflow).to be_complete
    end
  end

  describe '#failed?' do
    it 'checks if the status is :failed' do
      allow(workflow).to receive(:status).and_return(:complete)
      expect(workflow).to_not be_failed

      allow(workflow).to receive(:status).and_return(:failed)
      expect(workflow).to be_failed
    end
  end

  describe '#enqueued_at' do
    it 'fetches the workflow root enqueued time' do
      expect(workflow.enqueued_at).to eq root.enqueued_at
    end
  end

  describe '#run_at' do
    it 'fetches the workflow root run time' do
      expect(workflow.run_at).to eq root.run_at
    end
  end

  describe '#complete_at' do
    before do
      root.complete!
      level1.each(&:complete!)
    end

    context 'with some jobs incomplete' do
      it 'returns nil' do
        expect(workflow.complete_at).to be_nil
      end
    end

    context 'with all jobs complete' do
      let(:newest) { Time.now + 60*60 }
      before do
        level2.each(&:complete!)
        root[Sidekiq::Hierarchy::Job::COMPLETED_AT_FIELD] = newest.to_f.to_s  # avoid triggering callback
      end
      it 'returns the most recent completion time' do
        expect(workflow.complete_at.to_f).to eq newest.to_f
      end
    end
  end

  describe '#failed_at' do
    context 'with no failed jobs' do
      it 'returns nil' do
        expect(workflow.failed_at).to be_nil
      end
    end

    context 'with failed jobs' do
      before { level1.each(&:fail!) }
      it 'returns the earliest failure time' do
        expect(workflow.failed_at.to_f).to eq level1.map(&:failed_at).min.to_f
      end
    end
  end

  describe '#as_json' do
    it 'takes the hash of the root' do
      expect(workflow.as_json).to eq root.as_json
    end
  end

  describe '#to_s' do
    it 'returns a unique workflow identifier based on the hash' do
      expect(workflow.to_s).to eq Sidekiq.dump_json(workflow.as_json)
    end
  end
end
