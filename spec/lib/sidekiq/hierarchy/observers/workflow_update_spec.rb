require 'spec_helper'

describe Sidekiq::Hierarchy::Observers::WorkflowUpdate do
  let(:callback_registry) { Sidekiq::Hierarchy::CallbackRegistry.new }

  subject(:observer) { described_class.new }

  describe '#register' do
    let(:msg) { double('message') }
    before { observer.register(callback_registry) }
    it 'adds the observer to the registry listening for workflow updates' do
      expect(observer).to receive(:call).with(msg)
      callback_registry.publish(Sidekiq::Hierarchy::Notifications::WORKFLOW_UPDATE, msg)
    end
  end

  describe '#call' do
    let(:job_info) { {'class' => 'HardWorker', 'args' => [1, 'foo']} }
    let(:root) { Sidekiq::Hierarchy::Job.create('0', job_info) }
    let(:workflow) { Sidekiq::Hierarchy::Workflow.find(root) }

    let(:running_set) { Sidekiq::Hierarchy::RunningSet.new }
    let(:failed_set) { Sidekiq::Hierarchy::FailedSet.new }

    context 'when the workflow is new' do
      it 'adds the target workflow to the new status set' do
        expect(failed_set.contains?(workflow)).to be_falsey
        observer.call(workflow, :failed, workflow.status)
        expect(failed_set.contains?(workflow)).to be_truthy
      end
    end

    context 'when the workflow is already in a set' do
      before { running_set.add(workflow) }

      it 'removes the target workflow from its current status set' do
        expect(running_set.contains?(workflow)).to be_truthy
        observer.call(workflow, :failed, :running)
        expect(running_set.contains?(workflow)).to be_falsey
      end

      it 'adds the target workflow to the new status set' do
        expect(failed_set.contains?(workflow)).to be_falsey
        observer.call(workflow, :failed, :running)
        expect(failed_set.contains?(workflow)).to be_truthy
      end
    end
  end
end
