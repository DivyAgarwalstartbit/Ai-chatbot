Rails.application.routes.draw do
  root :to => 'home#index'
  get '/products', :to => 'products#index'

  namespace :knowledge_base do
    get '/', to: 'bases#index', as: :root
    resource :shipping_policy, only: %i[show update] do
      resource :attachment, only: %i[new create destroy], controller: 'policy_attachments',
               defaults: { policy_type: 'shipping_policy' }
      post :sync, controller: 'policy_syncs', defaults: { policy_type: 'shipping_policy' }
    end
    resource :return_policy, only: %i[show update] do
      resource :attachment, only: %i[new create destroy], controller: 'policy_attachments',
               defaults: { policy_type: 'return_policy' }
      post :sync, controller: 'policy_syncs', defaults: { policy_type: 'return_policy' }
    end
    resources :faqs, only: %i[index new show edit create update destroy] do
      resource :attachment, only: %i[new create destroy], controller: 'faq_attachments'
    end
    resource :faq_import, only: %i[new] do
      post :extract    # step 1: extract text + generate FAQ previews via Claude
      post :import     # step 2: save selected FAQs
    end
    resource :faq_suggestions, only: [] do
      post :suggest    # step 1: gather KB context, generate + deduplicate suggestions
      post :import     # step 2: save selected suggestions as FAQs
    end
    resources :documents, only: %i[index create destroy]
  end

  mount ShopifyApp::Engine, at: '/'
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
