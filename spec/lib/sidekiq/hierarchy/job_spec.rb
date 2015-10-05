require 'spec_helper'

describe Sidekiq::Hierarchy::Job do
  let(:root_jid) { '0' }
  let(:root) { described_class.create(root_jid) }
  let(:level1) { [described_class.create('1'), described_class.create('2')] }
  let(:level2) { [described_class.create('3'), described_class.create('4')] }

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
    let(:new_node) { described_class.create(new_jid) }
    it 'creates a new Job object and marks its status as enqueued' do
      expect(new_node).to be_a(described_class)
      expect(new_node.jid).to eq new_jid
      expect(new_node).to be_enqueued
    end
  end

  describe '#==' do
    let(:root_copy) { described_class.find(root_jid) }
    it 'compares jids' do
      expect(root).to_not eq level1.first
      expect(root).to eq root_copy
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

  describe '#add_child' do
    let(:new_job) { described_class.create('000000000000') }

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
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.enqueue!).to be_truthy
      expect(new_job).to be_enqueued
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
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.run!).to be_truthy
      expect(new_job).to be_running
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
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.complete!).to be_truthy
      expect(new_job).to be_complete
    end
  end

  describe '#requeued!' do
    let(:new_job) { described_class.find('000000000000') }
    it 'sets the job status to requeued' do
      expect(root.requeue!).to be_truthy
      expect(root).to be_requeued
      expect(root).to_not be_enqueued
      expect(root).to_not be_running
      expect(root).to_not be_complete
    end
    it 'operates correctly on an unpersisted job' do
      expect(new_job.requeue!).to be_truthy
      expect(new_job).to be_requeued
    end
  end
end
