require 'spec_helper'

require 'sidekiq/hierarchy/rack/middleware'

describe Sidekiq::Hierarchy::Rack::Middleware do
  def mock_env(jid, workflow)
    headers = {}
    headers[described_class::JOB_HEADER_KEY] = jid if jid
    headers[described_class::WORKFLOW_HEADER_KEY] = workflow if workflow
    @request = Rack::MockRequest.env_for('/', headers)
  end

  let(:app) do
    lambda do |_env|
      workflow_jid = Sidekiq::Hierarchy.current_workflow.jid if Sidekiq::Hierarchy.current_workflow
      jid = Sidekiq::Hierarchy.current_job.jid if Sidekiq::Hierarchy.current_job
      body = {workflow: workflow_jid, jid: jid}
      [200, {'Content-Type' => 'application/json'}, [body.to_json]]
    end
  end

  subject(:middleware) { described_class.new(app) }

  let(:jid) { '1234567890' }
  let(:workflow) { '246802468' }

  describe '#call' do
    context 'with no sidekiq-hierarchy headers set' do
      it 'does not set any request-local values' do
        status, headers, body = middleware.call(mock_env(nil, nil))
        jbody = JSON.parse(body.first)
        expect(jbody['jid']).to be_nil
        expect(jbody['workflow']).to be_nil
      end
    end

    context 'with only the Sidekiq-Hierarchy-Jid header set' do
      it 'does not set any request-local values' do
        status, headers, body = middleware.call(mock_env(jid, nil))
        jbody = JSON.parse(body.first)
        expect(jbody['jid']).to be_nil
        expect(jbody['workflow']).to be_nil
      end
    end

    context 'with only the Sidekiq-Hierarchy-Workflow header set' do
      it 'does not set any request-local values' do
        status, headers, body = middleware.call(mock_env(nil, workflow))
        jbody = JSON.parse(body.first)
        expect(jbody['jid']).to be_nil
        expect(jbody['workflow']).to be_nil
      end
    end

    context 'with both the Sidekiq-Hierarchy-Workflow and Sidekiq-Hierarchy-Jid headers set' do
      it 'sets Sidekiq::Hierarchy.current_workflow accordingly' do
        status, headers, body = middleware.call(mock_env(jid, workflow))
        jbody = JSON.parse(body.first)
        expect(jbody['jid']).to eq jid
        expect(jbody['workflow']).to eq workflow
      end
      it 'cleans up after the request' do
        status, headers, body = middleware.call(mock_env(jid, workflow))
        expect(Sidekiq::Hierarchy.current_job).to be_nil
        expect(Sidekiq::Hierarchy.current_workflow).to be_nil
      end
    end
  end
end
