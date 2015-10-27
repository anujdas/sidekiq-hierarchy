require 'rack'
require 'sidekiq/Hierarchy/http'

module Sidekiq
  module Hierarchy
    module Rack
      class Middleware
        # transform from http header to rack names
        JID_HEADER_KEY = "HTTP_#{Sidekiq::Hierarchy::Http::JID_HEADER.upcase.gsub('-','_')}".freeze
        WORKFLOW_HEADER_KEY = "HTTP_#{Sidekiq::Hierarchy::Http::WORKFLOW_HEADER.upcase.gsub('-','_')}".freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          Sidekiq::Hierarchy.current_jid = env[JID_HEADER_KEY]
          Sidekiq::Hierarchy.current_workflow = Workflow.find_by_jid(env[WORKFLOW_HEADER_KEY]) if env[WORKFLOW_HEADER_KEY]
          @app.call(env)
        ensure
          Sidekiq::Hierarchy.current_workflow = nil
          Sidekiq::Hierarchy.current_jid = nil
        end
      end
    end
  end
end
