require 'spec_helper'

require 'sidekiq/hierarchy/faraday/middleware'
require 'sidekiq/hierarchy/rack/middleware'

describe Sidekiq::Hierarchy::Faraday::Middleware do
  let(:faraday) do
    ::Faraday.new do |conn|
      conn.use described_class
      conn.adapter :test do |stub|
        stub.post('/') do |env|
          body = {workflow: env[:request_headers][Sidekiq::Hierarchy::Http::WORKFLOW_HEADER],
                  jid: env[:request_headers][Sidekiq::Hierarchy::Http::JID_HEADER]}
          [200, {'Content-Type' => 'application/json'}, body.to_json]
        end
      end
    end
  end

  let(:raw_response) { faraday.post '/' }
  subject(:response) { JSON.parse(raw_response.body) }

  after do
    Sidekiq::Hierarchy.current_jid = nil
    Sidekiq::Hierarchy.current_workflow = nil
  end

  describe '#call' do
    let(:jid) { '0123456789ab' }
    let(:workflow) { '02468024680' }

    context 'with neither jid nor workflow set' do
      it 'does not modify the request' do
        expect(response['jid']).to be_nil
        expect(response['workflow']).to be_nil
      end
    end

    context 'with current jid set' do
      before { Sidekiq::Hierarchy.current_jid = jid }
      it 'passes the jid via header' do
        expect(response['jid']).to eq jid
        expect(response['workflow']).to be_nil
      end
    end

    context 'with current jid and workflow set' do
      before do
        Sidekiq::Hierarchy.current_jid = jid
        Sidekiq::Hierarchy.current_workflow = workflow
      end
      it 'passes the jid and workflow via header' do
        expect(response['jid']).to eq jid
        expect(response['workflow']).to eq workflow
      end
    end
  end
end
