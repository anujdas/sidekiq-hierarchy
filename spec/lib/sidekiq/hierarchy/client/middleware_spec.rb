require 'spec_helper'

describe Sidekiq::Hierarchy::Client::Middleware do
  describe '#call' do
    context 'on job creation' do
      it "adds the created job to the current job's children list" do
      end

      it "records the current job as its child's parent" do
      end
    end

    context 'on job cancellation by a nested middleware' do
      xit 'marks the child job as finished' do
      end

      xit "performs cleanup on the current job's child list" do
      end
    end
  end
end
