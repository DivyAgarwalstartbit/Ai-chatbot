Rails.application.routes.draw do
  root to: "home#index"

  get "/home/check_app_embed_status", to: "home#check_app_embed_status"


  resource  :bot_settings, only: %i[show update]
  resources :conversations, only: %i[index show update]
  resources :tickets, only: %i[index show update] do
    member { post :reply }
  end

  namespace :app do
    resource :product_sync, only: %i[show create] do
      get :sync_status
    end
  end

  namespace :knowledge_base do
    get "/", to: "bases#index", as: :root

    resource :shipping_policy, only: %i[show update],
             controller: "policies", defaults: { policy_type: "shipping_policy" } do
      post :sync
      get    "attachment/new", action: :new_attachment,    as: :attachment_new
      post   "attachment",     action: :create_attachment, as: :attachment
      delete "attachment",     action: :destroy_attachment
    end

    resource :return_policy, only: %i[show update],
             controller: "policies", defaults: { policy_type: "return_policy" } do
      post :sync
      get    "attachment/new", action: :new_attachment,    as: :attachment_new
      post   "attachment",     action: :create_attachment, as: :attachment
      delete "attachment",     action: :destroy_attachment
    end

    resources :faqs, only: %i[index new show edit create update destroy] do
      collection do
        get  :import_panel
        post :extract
        post :import
        get  :suggestions_panel
        post :suggest
        post :suggest_import
      end

      member do
        get    "attachment/new", action: :new_attachment,    as: :attachment_new
        post   "attachment",     action: :create_attachment, as: :attachment
        delete "attachment",     action: :destroy_attachment
      end
    end

    resources :documents, only: %i[index create destroy]
  end

  get "/plans",            to: "plans#index",      as: :plans
  get "/billing/create",   to: "billing#create",   as: :billing_create
  get "/billing/callback", to: "billing#callback", as: :billing_callback
  post "/order_lookup", to: "orders_lookup#lookup"
  match "/order_lookup",
      to: "orders_lookup#options",
      via: :options


 # Shopify App Proxy — storefront requests forwarded here by Shopify
 # Shopify App Proxy routes
 get "/configuration",
    to: "output#configuration"

match "/configuration",
      to: "output#options",
      via: :options


post "/chat",
     to: "output#create"

match "/chat",
      to: "output#options",
      via: :options

post "/chat/stream",
     to: "output#stream"

match "/chat/stream",
      to: "output#options",
      via: :options

get "/chat/history",
    to: "output#history"

match "/chat/history",
      to: "output#options",
      via: :options

post "/chat/reset",
     to: "output#reset"

match "/chat/reset",
      to: "output#options",
      via: :options



  # Direct API routes

  get  "conversations/config", to: "output#configuration"
  post "conversations/chat",   to: "output#create"

  # Agent messages polling endpoint (used by the chat widget when in handoff mode)
  get   "/agent_messages", to: "agent_messages#index"
  match "/agent_messages", to: "agent_messages#options", via: :options

  mount ActionCable.server => "/cable"
  mount ShopifyApp::Engine, at: "/"

  get "up" => "rails/health#show", as: :rails_health_check
end
