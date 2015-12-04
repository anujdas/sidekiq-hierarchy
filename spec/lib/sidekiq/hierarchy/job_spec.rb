require 'spec_helper'

describe Sidekiq::Hierarchy::Job do
  let(:job_info) { {'class' => 'HardWorker', 'queue' => 'default'} }
  let(:root_jid) { '0' }
  let(:root) { described_class.create(root_jid, job_info) }
  let(:level1) { [described_class.create('1', job_info), described_class.create('2', job_info)] }
  let(:level2) { [described_class.create('3', job_info), described_class.create('4', job_info)] }

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

  describe '.find' do
    let(:existing_node) { described_class.find(root_jid) }
    it 'instantiates a Job object for the given jid' do
      expect(existing_node).to be_a(described_class)
      expect(existing_node.jid).to eq root_jid
    end
  end

  describe '.create' do
    let(:new_jid) { '000000000000' }
    let(:new_node) { described_class.create(new_jid, job_info) }

    it 'creates a new Job object' do
      expect(new_node).to be_a(described_class)
      expect(new_node.jid).to eq new_jid
    end

    it 'leaves the new Job with an unknown status' do
      expect(new_node.status).to be :unknown
    end

    context 'saving job info' do
      let(:expanded_job_info) { job_info.merge({'more_stuff' => ['abc', '123']}) }
      let(:job_info_with_contraints) { expanded_job_info.merge({'workflow_keys' => 'more_stuff'}) }

      let(:node_with_expanded_info) { described_class.create('1', expanded_job_info) }
      let(:node_with_constraints) { described_class.create('2', job_info_with_contraints) }

      it 'saves job info to redis' do
        expect(new_node[Sidekiq::Hierarchy::Job::INFO_FIELD]).to_not be_nil
      end

      it 'filters job info to a few default keys' do
        expect(node_with_expanded_info.info).to eq job_info
      end

      it 'permits additional job info via sidekiq option :workflow_keys' do
        expect(node_with_constraints.info).to eq expanded_job_info
      end
    end
  end

  describe '#delete' do
    before { root.delete }
    it 'recursively deletes the current job and all subjobs' do
      expect(described_class.find(root_jid).exists?).to be_falsey
      (level1 + level2).map(&:jid).each do |jid|
        expect(described_class.find(jid).exists?).to be_falsey
      end
    end
  end

  describe '#exists?' do
    let(:new_jid) { '000000000000' }
    let(:new_node) { described_class.find(new_jid) }
    it 'tests if the job has been persisted' do
      expect(root.exists?).to be_truthy
      expect(new_node.exists?).to be_falsey
    end
  end

  describe '#==' do
    let(:root_copy) { described_class.find(root_jid) }
    it 'compares jids' do
      expect(root).to_not eq level1.first
      expect(root).to eq root_copy
    end
  end

  describe '#[]' do
    let(:known_key) { 'known_key' }
    let(:value) { 'string' }
    before do
      Sidekiq.redis { |conn| conn.hset(root.redis_job_hkey, known_key, value) }
    end
    it 'retrieves attributes from redis' do
      expect(root[known_key]).to eq value
    end
    it 'returns nil if the attribute is unset' do
      expect(root['unknown_key']).to be_nil
    end
  end

  describe '#[]=' do
    let(:node) { described_class.find('000000000000') }
    it 'sets attributes in redis' do
      node['attribute'] = 'value'
      expect(Sidekiq.redis { |conn| conn.hget(node.redis_job_hkey, 'attribute') }).to eq 'value'
    end
    it 'creates the redis entry if none exists' do
      expect(Sidekiq.redis { |conn| conn.exists(node.redis_job_hkey) }).to be_falsey
      node['attribute'] = 'value'
      expect(Sidekiq.redis { |conn| conn.exists(node.redis_job_hkey) }).to be_truthy
    end
  end

  describe '#info' do
    it 'retrieves the job info from redis' do
      expect(root.info).to eq job_info
    end
  end

  describe '#parent' do
    it 'is nil for a root node' do
      expect(root.parent).to be_nil
    end
    it 'returns a Job for a non-root node' do
      expect(level1.first.parent).to eq root
      expect(level2.first.parent).to eq level1.first
    end
  end

  describe '#children' do
    it 'is an empty list for a leaf node' do
      expect(level2.first.children).to be_empty
    end
    it 'returns a list of immediate child Jobs' do
      expect(root.children).to eq level1
      expect(level1.first.children).to eq level2
    end
  end

  describe '#root?' do
    it 'is true for a parentless node' do
      expect(root).to be_root
    end
    it 'is false for a node with a parent' do
      expect(level1.first).to_not be_root
      expect(level2.first).to_not be_root
    end
  end

  describe '#leaf?' do
    it 'is true for a childless node' do
      expect(level1.last).to be_a_leaf
      expect(level2.first).to be_a_leaf
    end
    it 'is false for a node with children' do
      expect(root).to_not be_a_leaf
      expect(level1.first).to_not be_a_leaf
    end
  end

  describe '#root' do
    it 'returns the job itself if it is a root' do
      expect(root.root).to eq root
    end
    it 'walks the workflow up to the root from any intermediate job' do
      expect(level1.first.root).to eq root
      expect(level2.first.root).to eq root
    end
  end

  describe '#leaves' do
    it 'walks the tree to return all childless nodes underneath this one' do
      expect(root.leaves).to match level2 + [level1.last]
      expect(level1.first.leaves).to match level2
    end
    it 'returns a list of itself if it is a leaf' do
      expect(level1.last.leaves).to eq [level1.last]
      expect(level2.first.leaves).to eq [level2.first]
    end
  end

  describe '#subtree_jobs' do
    it 'returns a lazy Enumerator' do
      expect(root.subtree_jobs).to be_an Enumerator
      expect(root.subtree_jobs.first.jid).to eq root.jid
      expect(root.subtree_jobs.count).to eq ([root] + level1 + level2).length
    end
    it 'traverses all nodes depth-first reverse-order' do
      expect(root.subtree_jobs.map(&:jid)).to eq ['0', '2', '1', '4', '3']
    end
  end

  describe '#subtree_size' do
    let(:new_job) { described_class.create('000000000000', job_info) }
    it 'is one for a newly created job' do
      expect(new_job.subtree_size).to eq 1
    end
    it 'fetches the subtree size from redis' do
      new_job[described_class::SUBTREE_SIZE_FIELD] = 10
      expect(new_job.subtree_size).to eq 10
    end
  end

  describe '#increment_subtree_size' do
    let(:incr) { 10 }

    it 'adds the increment to the job subtree size' do
      expect { root.increment_subtree_size(incr) }.
        to change { root.subtree_size }.
        by(incr)
    end

    it 'adds the increment to each parent subtree size' do
      expect { level2.last.increment_subtree_size(incr) }.
        to change { level2.last.parent.subtree_size }.
        by(incr)

      expect { level2.last.increment_subtree_size(incr) }.
        to change { root.subtree_size }.
        by(incr)
    end

    it 'defaults to an increment of 1' do
      expect { root.increment_subtree_size }.
        to change { root.subtree_size }.
        by(1)
    end
  end

  describe '#finished_subtree_size' do
    let(:new_job) { described_class.create('000000000000', job_info) }
    it 'is zero for a newly created job' do
      expect(new_job.finished_subtree_size).to eq 0
    end
    it 'fetches the finished subtree size from redis' do
      new_job[described_class::FINISHED_SUBTREE_SIZE_FIELD] = 10
      expect(new_job.finished_subtree_size).to eq 10
    end
  end

  describe '#increment_finished_subtree_size' do
    let(:incr) { 10 }

    it 'adds the increment to the job subtree size' do
      expect { root.increment_finished_subtree_size(incr) }.
        to change { root.finished_subtree_size }.
        by(incr)
    end

    it 'adds the increment to each parent subtree size' do
      expect { level2.last.increment_finished_subtree_size(incr) }.
        to change { level2.last.parent.finished_subtree_size }.
        by(incr)

      expect { level2.last.increment_finished_subtree_size(incr) }.
        to change { root.finished_subtree_size }.
        by(incr)
    end

    it 'defaults to an increment of 1' do
      expect { root.increment_finished_subtree_size }.
        to change { root.finished_subtree_size }.
        by(1)
    end
  end

  describe '#add_child' do
    let(:new_job) { described_class.create('000000000000', job_info) }

    it "adds the child to the parent's children list" do
      expect { root.add_child(new_job) }.
        to change { root.children }.
        from(level1).
        to(level1 + [new_job])
    end

    it "adds the parent to the child's info" do
      expect { root.add_child(new_job) }.
        to change { new_job.parent }.
        from(nil).
        to(root)
    end

    it "increments the parent's subtree size" do
      expect(root).to receive(:increment_subtree_size).with(new_job.subtree_size)
      root.add_child(new_job)
    end

    it "increments the parent's finished subtree size" do
      expect(root).to receive(:increment_finished_subtree_size).with(new_job.finished_subtree_size)
      root.add_child(new_job)
    end
  end

  describe '#workflow' do
    it 'returns the workflow containing the job' do
      expect(root.workflow.root).to eq root
      expect(root.workflow.jobs.to_a).to match_array [root] + level1 + level2

      expect(level1.first.workflow.root).to eq root
      expect(level1.first.workflow.jobs.to_a).to match_array [root] + level1 + level2
    end
  end

  describe '#enqueue!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to enqueued' do
      root.enqueue!
      expect(root).to be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_complete
      expect(root).to_not be_requeued
      expect(root).to_not be_failed
      expect(root).to_not be_finished
    end
    it 'operates correctly on an unpersisted job' do
      new_job.enqueue!
      expect(new_job).to be_enqueued
    end
    it 'sets the enqueued-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      new_job.enqueue!
      expect(new_job.enqueued_at).to eq Time.at(0)
    end
    it 'does not change the finished subtree size' do
      expect { new_job.enqueue! }.
        to_not change { new_job.finished_subtree_size }
    end
  end

  describe '#run!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to running' do
      root.run!
      expect(root).to be_running
      expect(root).to_not be_enqueued
      expect(root).to_not be_complete
      expect(root).to_not be_requeued
      expect(root).to_not be_failed
      expect(root).to_not be_finished
    end
    it 'operates correctly on an unpersisted job' do
      new_job.run!
      expect(new_job).to be_running
    end
    it 'sets the run-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      root.run!
      expect(root.run_at).to eq Time.at(0)
    end
    it 'does not change the finished subtree size' do
      expect { new_job.run! }.
        to_not change { new_job.finished_subtree_size }
    end
  end

  describe '#complete!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to complete' do
      root.complete!
      expect(root).to be_complete
      expect(root).to be_finished
      expect(root).to_not be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_requeued
      expect(root).to_not be_failed
    end
    it 'operates correctly on an unpersisted job' do
      new_job.complete!
      expect(new_job).to be_complete
    end
    it 'sets the completed-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      root.complete!
      expect(root.complete_at).to eq Time.at(0)
      expect(root.failed_at).to be_nil
    end
    it 'increments the finished subtree size' do
      expect { new_job.complete! }.
        to change { new_job.finished_subtree_size }.
        by(1)
    end
  end

  describe '#requeue!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to requeued' do
      root.requeue!
      expect(root).to be_requeued
      expect(root).to_not be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_complete
      expect(root).to_not be_failed
      expect(root).to_not be_finished
    end
    it 'operates correctly on an unpersisted job' do
      new_job.requeue!
      expect(new_job).to be_requeued
    end
    it 'does not change the finished subtree size' do
      expect { new_job.requeue! }.
        to_not change { new_job.finished_subtree_size }
    end
  end

  describe '#fail!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to failed' do
      root.fail!
      expect(root).to be_failed
      expect(root).to be_finished
      expect(root).to_not be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_complete
      expect(root).to_not be_requeued
    end
    it 'operates correctly on an unpersisted job' do
      new_job.fail!
      expect(new_job).to be_failed
    end
    it 'sets the failed-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      root.fail!
      expect(root.failed_at).to eq Time.at(0)
      expect(root.complete_at).to be_nil
    end
    it 'increments the finished subtree size' do
      expect { new_job.fail! }.
        to change { new_job.finished_subtree_size }.
        by(1)
    end
  end

  describe '#status' do
    let(:job) { described_class.find('000000000000') }
    it 'reflects the current status as a symbol' do
      job.enqueue!
      expect(job.status).to eq :enqueued

      job.run!
      expect(job.status).to eq :running

      job.complete!
      expect(job.status).to eq :complete

      job.requeue!
      expect(job.status).to eq :requeued

      job.fail!
      expect(job.status).to eq :failed
    end
    it 'returns unknown if the status does not match a known value' do
      job[described_class::STATUS_FIELD] = nil
      expect(job.status).to eq :unknown
    end
  end

  describe '#as_json' do
    let(:json) { job.as_json }

    context 'for a childless job' do
      let(:job) { level2.last }
      it 'produces a hash containing the class and no children' do
        expect(json[:k]).to eq job_info['class']
        expect(json[:c]).to eq []
      end
    end

    context 'for a job with children' do
      let(:job) { level1.first }
      it 'produces a hash of the subtree containing class and children' do
        expect(json[:k]).to eq job_info['class']
        expect(json[:c].length).to eq level2.length
        expect(json[:c].map{|j| j[:k]}).to eq [job_info['class'], job_info['class']]
      end
    end

    context 'for arbitrarily ordered children' do
      let(:child1) { described_class.create('10', {'class' => 'a'}) }
      let(:child2) { described_class.create('11', {'class' => 'b'}) }
      let(:tree1) do
        root = described_class.create('12', {'class' => 'c'})
        root.add_child(child1)
        root.add_child(child2)
        root
      end
      let(:tree2) do
        root = described_class.create('13', {'class' => 'c'})
        root.add_child(child2)
        root.add_child(child1)
        root
      end
      it 'returns the same hash' do
        expect(tree1.as_json).to eq tree2.as_json
      end
    end
  end
end
