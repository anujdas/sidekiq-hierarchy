require 'faraday'
require 'sidekiq/hierarchy/http'

module Sidekiq
  module Hierarchy
    module Faraday
      class Middleware < ::Faraday::Middleware
        def call(env)
          if Sidekiq::Hierarchy.current_workflow && Sidekiq::Hierarchy.current_jid
            env[:request_headers][Sidekiq::Hierarchy::Http::JID_HEADER] = Sidekiq::Hierarchy.current_jid
            env[:request_headers][Sidekiq::Hierarchy::Http::WORKFLOW_HEADER] = Sidekiq::Hierarchy.current_workflow.jid
          end
          @app.call(env)
        end
      end
    end
  end
end
