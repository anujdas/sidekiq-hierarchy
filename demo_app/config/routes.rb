require 'sidekiq/web'
require 'sidekiq/hierarchy/web'

Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'

  root to: 'jobs#new'
  resources :jobs, only: [:new, :create]
end
