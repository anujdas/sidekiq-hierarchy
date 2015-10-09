require 'spec_helper'

describe Sidekiq::Hierarchy::Job do
  let(:job_info) { {'class' => 'HardWorker', 'args' => [1, 'foo']} }
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

  shared_examples_for 'redis_pool support' do
    let(:alt_redis) { Redis.new }
    let(:alt_redis_pool) { ConnectionPool.new { alt_redis } }
    it 'defaults to using the Sidekiq redis connection' do
      subject.send(:redis) { |c| c.set 'test', '1' }
      expect(Sidekiq.redis { |c| c.get('test') }).to eq '1'
    end
    it 'accepts an alternate redis_pool' do
      alt_subject.send(:redis) { |c| c.set 'test', '1' }
      expect(alt_redis.get('test')).to eq '1'
    end
  end

  describe '.find' do
    let(:existing_node) { described_class.find(root_jid) }
    it 'instantiates a Job object for the given jid' do
      expect(existing_node).to be_a(described_class)
      expect(existing_node.jid).to eq root_jid
    end
    it_behaves_like 'redis_pool support' do
      let(:subject) { described_class.find(root_jid) }
      let(:alt_subject) { described_class.find(root_jid, alt_redis_pool) }
    end
  end

  describe '.create' do
    let(:new_jid) { '000000000000' }
    let(:new_node) { described_class.create(new_jid, job_info) }
    it 'creates a new Job object' do
      expect(new_node).to be_a(described_class)
      expect(new_node.jid).to eq new_jid
    end
    it 'marks the new Job as enqueued' do
      expect(new_node).to be_enqueued
    end
    it 'saves the job info to redis' do
      expect(new_node.info).to eq job_info
    end
    it_behaves_like 'redis_pool support' do
      let(:subject) { described_class.create(root_jid, job_info) }
      let(:alt_subject) { described_class.create(root_jid, job_info, alt_redis_pool) }
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
    it_behaves_like 'redis_pool support' do
      let(:subject) { level1.first.parent }
      let(:alt_subject) { described_class.create(level1.first.jid, job_info, alt_redis_pool) }
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
    it_behaves_like 'redis_pool support' do
      let(:subject) { root.children.first }
      let(:alt_subject) { described_class.create(root_jid, job_info, alt_redis_pool) }
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
      expect(root.enqueue!).to be_truthy
      expect(root).to be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_complete
      expect(root).to_not be_requeued
      expect(root).to_not be_failed
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.enqueue!).to be_truthy
      expect(new_job).to be_enqueued
    end
    it 'sets the enqueued-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      root.enqueue!
      expect(root.enqueued_at).to eq Time.at(0)
    end
  end

  describe '#run!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to running' do
      expect(root.run!).to be_truthy
      expect(root).to be_running
      expect(root).to_not be_enqueued
      expect(root).to_not be_complete
      expect(root).to_not be_requeued
      expect(root).to_not be_failed
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.run!).to be_truthy
      expect(new_job).to be_running
    end
    it 'sets the run-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      root.run!
      expect(root.run_at).to eq Time.at(0)
    end
  end

  describe '#complete!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to complete' do
      expect(root.complete!).to be_truthy
      expect(root).to be_complete
      expect(root).to_not be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_requeued
      expect(root).to_not be_failed
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.complete!).to be_truthy
      expect(new_job).to be_complete
    end
    it 'sets the completed-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      root.complete!
      expect(root.complete_at).to eq Time.at(0)
      expect(root.failed_at).to be_nil
    end
  end

  describe '#requeue!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to requeued' do
      expect(root.requeue!).to be_truthy
      expect(root).to be_requeued
      expect(root).to_not be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_complete
      expect(root).to_not be_failed
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.requeue!).to be_truthy
      expect(new_job).to be_requeued
    end
  end

  describe '#fail!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to failed' do
      expect(root.fail!).to be_truthy
      expect(root).to be_failed
      expect(root).to_not be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_complete
      expect(root).to_not be_requeued
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.fail!).to be_truthy
      expect(new_job).to be_failed
    end
    it 'sets the failed-at timestamp' do
      allow(Time).to receive(:now).and_return(Time.at(0))
      root.fail!
      expect(root.failed_at).to eq Time.at(0)
      expect(root.complete_at).to be_nil
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
