require 'spec_helper'

shared_examples_for 'workflow set' do
  subject(:workflow_set) { described_class.new }

  let(:job_info) { {'class' => 'HardWorker'} }
  let(:root) { Sidekiq::Hierarchy::Job.create('0', job_info) }
  let(:level1) { [Sidekiq::Hierarchy::Job.create('1', job_info), Sidekiq::Hierarchy::Job.create('2', job_info)] }
  let(:level2) { [Sidekiq::Hierarchy::Job.create('3', job_info), Sidekiq::Hierarchy::Job.create('4', job_info)] }

  before do
    level1.each { |c| root.add_child(c) }
    level2.each { |c| level1.first.add_child(c) }
  end

  let(:workflow) { Sidekiq::Hierarchy::Workflow.find(root) }

  before do  # remove from workflow_set to establish testing baseline
    Sidekiq.redis { |c| c.zrem(workflow_set.redis_zkey, workflow.jid) }
  end

  describe '#==' do
    it 'verifies the other workflow set has the same type' do
      expect(workflow_set).to eq described_class.new
      expect(workflow_set).to_not eq Sidekiq::Hierarchy::WorkflowSet.new('other_status')
    end
  end

  describe '#size' do
    before { Sidekiq.redis { |c| c.del(zset) } }
    it 'returns the size of the set' do
      expect { Sidekiq.redis { |c| c.zadd(zset, 0, 0) } }
        .to change { workflow_set.size }
        .from(0)
        .to(1)
    end
  end

  describe '#add' do
    let(:time) { 10000.0 }
    before { allow(Time).to receive(:now).and_return(Time.at(time)) }

    it 'inserts a workflow into the set by root jid ordered on timestamp' do
      workflow_set.add(workflow)
      expect(Sidekiq.redis { |c| c.zscore(zset, workflow.root.jid) }).to eq time
    end

    it 'updates timestamp given a duplicate workflow' do
      workflow_set.add(workflow)

      allow(Time).to receive(:now).and_return(Time.at(time + 1))
      workflow_set.add(workflow)

      expect(Sidekiq.redis { |c| c.zscore(zset, workflow.root.jid) }).to eq time + 1
    end
  end

  describe '#contains?' do
    it 'tests whether the set includes the workflow' do
      expect(workflow_set.contains?(workflow)).to be_falsey
      workflow_set.add(workflow)
      expect(workflow_set.contains?(workflow)).to be_truthy
    end
  end

  describe '#remove' do
    context 'when the workflow is persisted' do
      it 'raises a runtime error' do
        expect { workflow_set.remove(workflow) }.to raise_error(RuntimeError)
      end
    end

    context 'when the workflow has been deleted' do
      before { root.delete }

      it 'removes the workflow from the set' do
        workflow_set.add(workflow)
        workflow_set.remove(workflow)

        expect(Sidekiq.redis { |c| c.zscore(zset, workflow.root.jid) }).to be_nil
      end

      it 'does nothing if the workflow is not in the set' do
        workflow_set.remove(workflow)

        expect(Sidekiq.redis { |c| c.zscore(zset, workflow.root.jid) }).to be_nil
      end
    end
  end

  describe '#move' do
    context 'from an existing set matching the workflow status' do
      let(:old_workflow_set) { workflow.workflow_set }
      before { workflow.root.enqueue! }
      it 'moves the workflow' do
        workflow_set.move(workflow, old_workflow_set)
        unless workflow_set == old_workflow_set
          expect(old_workflow_set.contains?(workflow)).to be_falsey
        end
        expect(workflow_set.contains?(workflow)).to be_truthy
      end
    end

    context 'for a workflow not in any set' do
      it 'adds the workflow to the new set' do
        workflow_set.move(workflow)
        expect(workflow_set.contains?(workflow)).to be_truthy
      end
    end
  end

  describe '#each' do
    let(:workflows) { (10..20).map { |i| Sidekiq::Hierarchy::Workflow.find_by_jid(i.to_s) } }
    before do
      workflow_set.each(&:delete)
      workflows.each { |w| workflow_set.add(w) }
    end
    it 'yields every element of the set from most recent to least' do
      expect(workflow_set.each.map(&:jid)).to eq workflows.reverse.map(&:jid)
    end
    it 'tolerates set modification during iteration' do
      jids = workflow_set.each.map { |result| Sidekiq.redis { |c| c.del(workflow_set.redis_zkey) }; result.jid }
      expect(jids).to eq workflows.reverse.map(&:jid)
    end
  end
end

shared_examples_for 'pruning workflow set' do
  include_examples 'workflow set'

  describe '.max_workflows' do
    context 'with :dead_max_workflows set in sidekiq opts' do
      before { Sidekiq.options[:dead_max_workflows] = 100 }
      after { Sidekiq.options[:dead_max_workflows] = nil }
      it 'returns the set value' do
        expect(described_class.max_workflows).to eq Sidekiq.options[:dead_max_workflows]
      end
    end
    context 'without :dead_max_workflows set in sidekiq opts' do
      it 'returns the value of the :dead_max_jobs option' do
        expect(described_class.max_workflows).to eq Sidekiq.options[:dead_max_jobs]
      end
    end
  end

  describe '.timeout' do
    it 'returns the value of the :dead_timeout_in_seconds option' do
      expect(described_class.timeout).to eq Sidekiq.options[:dead_timeout_in_seconds]
    end
  end

  describe '#add' do
    it 'prunes after adding' do
      expect(workflow_set).to receive(:prune).once
      workflow_set.add(workflow)
    end
  end

  describe '#prune' do
    let(:max_workflows) { 15 }
    let(:timeout) { 60 }  # seconds

    let(:pruned_workflows) do
      max_workflows.times
        .map { |i| Sidekiq::Hierarchy::Job.create(i.to_s, job_info) }
        .map { |job| Sidekiq::Hierarchy::Workflow.new(job) }
    end
    let(:kept_workflows) do
      max_workflows.times.map { |i| i + max_workflows }
        .map { |i| Sidekiq::Hierarchy::Job.create(i.to_s, job_info) }
        .map { |job| Sidekiq::Hierarchy::Workflow.new(job) }
    end

    context 'with workflows older than the timeout' do
      let(:now) { Time.at(10000) }
      before do
        allow(Time).to receive(:now).and_return(now - timeout - 1)
        pruned_workflows.each { |w| workflow_set.add(w) }
        allow(Time).to receive(:now).and_return(now)
        kept_workflows.each { |w| workflow_set.add(w) }
      end

      before { Sidekiq.options[:dead_timeout_in_seconds] = timeout }
      after { Sidekiq.options[:dead_timeout_in_seconds] = 180*24*60*60 }

      it 'removes them from the set' do
        workflow_set.prune
        expect(pruned_workflows.map(&:root).none?(&:exists?)).to be_truthy
        expect(kept_workflows.map(&:root).all?(&:exists?)).to be_truthy
      end
    end

    context 'with more workflows than the max cap' do
      before { (pruned_workflows + kept_workflows).each { |w| workflow_set.add(w) } }

      before { Sidekiq.options[:dead_max_workflows] = max_workflows }
      after { Sidekiq.options[:dead_max_workflows] = nil }

      it 'removes the oldest extras from the set' do
        workflow_set.prune
        expect(pruned_workflows.map(&:root).none?(&:exists?)).to be_truthy
        expect(kept_workflows.map(&:root).all?(&:exists?)).to be_truthy
      end
    end
  end
end

describe Sidekiq::Hierarchy::WorkflowSet do
  describe '.for_status' do
    it 'returns the running set for status :running' do
      expect(described_class.for_status(:running)).to be_an_instance_of Sidekiq::Hierarchy::RunningSet
    end
    it 'returns the complete set for status :complete' do
      expect(described_class.for_status(:complete)).to be_an_instance_of Sidekiq::Hierarchy::CompleteSet
    end
    it 'returns the failed set for status :failed' do
      expect(described_class.for_status(:failed)).to be_an_instance_of Sidekiq::Hierarchy::FailedSet
    end
  end

  describe '#new' do
    it 'requires a status' do
      expect { described_class.new(nil) }.to raise_error(ArgumentError)
      expect { described_class.new('status') }.to_not raise_error
    end
  end
end

describe Sidekiq::Hierarchy::RunningSet do
  it_behaves_like 'workflow set' do
    let(:zset) { 'hierarchy:set:running' }
  end
end

describe Sidekiq::Hierarchy::CompleteSet do
  it_behaves_like 'pruning workflow set' do
    let(:zset) { 'hierarchy:set:complete' }
  end
end

describe Sidekiq::Hierarchy::FailedSet do
  it_behaves_like 'pruning workflow set' do
    let(:zset) { 'hierarchy:set:failed' }
  end
end
