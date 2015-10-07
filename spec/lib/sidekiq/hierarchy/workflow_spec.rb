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

  subject(:workflow) { described_class.new(root.jid) }

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

  describe '#running?' do
    before do
      root.complete!
      (level1 + level2).each(&:complete!)
    end
    it 'is true if any job is still enqueued' do
      level2.first.enqueue!
      expect(workflow).to be_running
    end
    it 'is true if any job was requeued' do
      level2.first.requeue!
      expect(workflow).to be_running
    end
    it 'is true if any job is still running' do
      level2.first.run!
      expect(workflow).to be_running
    end
    it 'is false if all jobs are complete' do
      expect(workflow).to_not be_running
    end
  end

  describe '#complete?' do
    before do
      root.complete!
      (level1 + level2).each(&:complete!)
    end
    it 'is false if any job is still enqueued' do
      level2.first.enqueue!
      expect(workflow).to_not be_complete
    end
    it 'is false if any job is still running' do
      level2.first.run!
      expect(workflow).to_not be_complete
    end
    it 'is false if any job failed' do
      level2.first.fail!
      expect(workflow).to_not be_complete
    end
    it 'is true if all jobs are complete' do
      expect(workflow).to be_complete
    end
  end

  describe '#failed?' do
    before do
      root.complete!
      (level1 + level2).each(&:complete!)
    end
    it 'is true if any job failed' do
      level2.first.fail!
      expect(workflow).to be_failed
    end
    it 'is false if no job failed' do
      expect(workflow).to_not be_failed
    end
  end
end
