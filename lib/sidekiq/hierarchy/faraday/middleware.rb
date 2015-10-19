require 'faraday'
require 'sidekiq/Hierarchy/http'

module Sidekiq
  module Hierarchy
    module Faraday
      class Middleware < ::Faraday::Middleware
        def call(env)
          env[:request_headers][Sidekiq::Hierarchy::Http::JID_HEADER] = Sidekiq::Hierarchy.current_jid if Sidekiq::Hierarchy.current_jid
          env[:request_headers][Sidekiq::Hierarchy::Http::WORKFLOW_HEADER] = Sidekiq::Hierarchy.current_workflow.jid if Sidekiq::Hierarchy.current_workflow
          @app.call(env)
        end
      end
    end
  end
end
