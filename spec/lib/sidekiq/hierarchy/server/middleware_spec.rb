require 'spec_helper'

describe Sidekiq::Hierarchy::Server::Middleware do
  describe '#call' do
    context 'on job start' do
      it 'updates workflow status on the current job' do
      end
    end

    context 'on successful job completion' do
      it 'marks itself as completed' do
      end

      it 'reports workflow completion by walking the tree' do
      end
    end

    context 'on job failure' do
      xit 'notes the retry attempt on the current job' do
      end

      xit 'adds the retried job to the workflow as a child' do
      end

      xit 'marks the workflow as failed if no more retries are possible' do
      end
    end
  end
end
