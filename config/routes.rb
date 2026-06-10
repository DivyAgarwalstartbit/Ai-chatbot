Rails.application.routes.draw do
  root to: "home#index"

  get "/home/check_app_embed_status", to: "home#check_app_embed_status"

  get "/products", to: "products#index"

  resource  :bot_settings, only: %i[show update]
  resources :conversations, only: %i[index show]
  resources :tickets,       only: %i[index show update]

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

  scope "/apps/ai-chat" do
    namespace :api do
      post "/chat", to: "conversations#create"
      match "/chat", to: "conversations#options", via: :options
    end
  end

  # Shopify App Proxy — storefront requests forwarded here by Shopify
  get   "/apps/ai-chat/config", to: "api/conversations#config"
  match "/apps/ai-chat/config", to: "api/conversations#options", via: :options
  post  "/apps/ai-chat/chat",   to: "api/conversations#create"
  match "/apps/ai-chat/chat",   to: "api/conversations#options", via: :options
  get "/ping", to: "ping#index"
  mount ShopifyApp::Engine, at: "/"

  get "up" => "rails/health#show", as: :rails_health_check
end
