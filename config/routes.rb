Rails.application.routes.draw do
  root :to => 'home#index'
  get '/products', :to => 'products#index'
  resource :bot_settings, only: %i[show update]

  namespace :knowledge_base do
    get '/', to: 'bases#index', as: :root

    # Shipping Policy — show, update, sync, attachment
    resource :shipping_policy, only: %i[show update],
             controller: 'policies', defaults: { policy_type: 'shipping_policy' } do
      post :sync
      get  'attachment/new', action: :new_attachment, as: :attachment_new
      post 'attachment',     action: :create_attachment, as: :attachment
      delete 'attachment',   action: :destroy_attachment
    end

    # Return Policy — identical surface, different policy_type default
    resource :return_policy, only: %i[show update],
             controller: 'policies', defaults: { policy_type: 'return_policy' } do
      post :sync
      get  'attachment/new', action: :new_attachment, as: :attachment_new
      post 'attachment',     action: :create_attachment, as: :attachment
      delete 'attachment',   action: :destroy_attachment
    end

    # FAQs — CRUD + import + suggestions + attachments
    resources :faqs, only: %i[index new show edit create update destroy] do
      collection do
        get  :import_panel     # renders the import form panel (turbo frame)
        post :extract          # step 1: extract text + generate FAQ previews
        post :import           # step 2: save selected FAQs from import
        get  :suggestions_panel # renders the suggestions prompt panel
        post :suggest           # step 1: generate AI suggestions
        post :suggest_import    # step 2: save selected suggestions as FAQs
      end

      member do
        get    'attachment/new', action: :new_attachment, as: :attachment_new
        post   'attachment',     action: :create_attachment, as: :attachment
        delete 'attachment',     action: :destroy_attachment
      end
    end

    resources :documents, only: %i[index create destroy]
  end

  mount ShopifyApp::Engine, at: '/'

  get "up" => "rails/health#show", as: :rails_health_check
end
