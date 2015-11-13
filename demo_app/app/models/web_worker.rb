require 'sidekiq/hierarchy/faraday/middleware'

class WebWorker
  include Sidekiq::Worker

  ROOT_PATH = 'http://localhost:3000'

  sidekiq_options workflow: true, queue: :ultralow

  def perform(*args)
    conn = Faraday.new(url: ROOT_PATH) do |f|
      f.request :url_encoded
      f.use Sidekiq::Hierarchy::Faraday::Middleware
      f.adapter Faraday.default_adapter
    end

    conn.post '/jobs', worker: ParentWorker.name
  end
end
