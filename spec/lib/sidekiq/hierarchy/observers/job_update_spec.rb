require 'spec_helper'

describe Sidekiq::Hierarchy::Observers::JobUpdate do
  let(:callback_registry) { Sidekiq::Hierarchy::CallbackRegistry.new }

  subject(:observer) { described_class.new }

  describe '#register' do
    let(:msg) { double('message') }
    before { observer.register(callback_registry) }
    it 'adds the observer to the registry listening for job updates' do
      expect(observer).to receive(:call).with(msg)
      callback_registry.publish(Sidekiq::Hierarchy::Notifications::JOB_UPDATE, msg)
    end
  end

  describe '#call' do
    let(:job_info) { {'class' => 'HardWorker', 'args' => [1, 'foo']} }
    let(:root) { Sidekiq::Hierarchy::Job.create('0', job_info) }
    let(:job) { Sidekiq::Hierarchy::Job.create('1', job_info) }
    let(:workflow) { Sidekiq::Hierarchy::Workflow.find(root) }

    # Workflow: root(0) -> job(1)
    before { root.add_child(job) }

    it 'updates the related workflow using the new status' do
      observer.call(root.jid, :running, job.status)
      expect(workflow).to be_running
      observer.call(job.jid, :failed, job.status)
      expect(workflow).to be_failed
    end
  end
end
