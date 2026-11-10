# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  ActiveAdmin.routes(self)

  post "webhooks/sendit/:store_slug", to: "webhooks/sendit#create", as: :sendit_webhook
  post "webhooks/ozon/:store_slug", to: "webhooks/ozon#create", as: :ozon_webhook
  post "webhooks/ameex/:store_slug", to: "webhooks/ameex#create", as: :ameex_webhook
  post "webhooks/seallo", to: "webhooks/seallo#create"
  post "webhooks/store_orders/:token", to: "webhooks/store_orders#create", as: :store_orders_webhook
  post "webhooks/shopify/uninstalled", to: "webhooks/shopify_lifecycle#uninstall", as: :shopify_uninstalled

  # Meta Login redirect URI, data deletion callback and its public status page (platform apex).
  get "auth/meta/callback", to: "meta_oauth#callback", as: :meta_oauth_callback
  post "auth/meta/data-deletion", to: "webhooks/meta_data_deletion#create", as: :meta_data_deletion
  get "auth/meta/data-deletion/:code", to: "meta_oauth#deletion_status", as: :meta_data_deletion_status, constraints: { code: /[0-9a-f]{24}/ }
  post "consent/tracking", to: "consents#tracking", as: :tracking_consent

  get "/.well-known/oauth-protected-resource/platform/mcp", to: "platform_oauth/metadata#protected_resource"
  get "/.well-known/oauth-authorization-server/platform/oauth", to: "platform_oauth/metadata#authorization_server"
  get "/platform/oauth/.well-known/oauth-authorization-server", to: "platform_oauth/metadata#authorization_server"
  get "/platform/oauth/authorize", to: "platform_oauth/authorizations#show", as: :platform_oauth_authorize
  post "/platform/oauth/authorize", to: "platform_oauth/authorizations#create"
  post "/platform/oauth/token", to: "platform_oauth/tokens#create", as: :platform_oauth_token
  match "/platform/oauth/token", to: "platform_oauth/tokens#preflight", via: :options

  post "/graphql", to: "graphql#execute"
  match "/platform/mcp", to: "platform_mcp#handle", via: %i[get post delete]
  match "/mcp", to: "mcp#handle", via: %i[get post delete]
  get "/sitemap.xml", to: "sitemaps#show", as: :sitemap, defaults: { format: :xml }

  get "/.well-known/oauth-protected-resource", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-protected-resource/mcp", to: "oauth/metadata#protected_resource"
  get "/.well-known/oauth-authorization-server", to: "oauth/metadata#authorization_server"
  get "/.well-known/oauth-authorization-server/mcp", to: "oauth/metadata#authorization_server"
  get "/.well-known/openid-configuration", to: "oauth/metadata#authorization_server"
  get "/.well-known/agent-skills/index.json", to: "skills#index"
  get "/.well-known/agent-skills/morea-catalog/SKILL.md", to: "skills#show"
  get "/.well-known/skills/index.json", to: "skills#legacy_index"
  get "/.well-known/skills/morea-catalog/SKILL.md", to: "skills#show"

  get "/oauth/authorize", to: "oauth/authorizations#show", as: :oauth_authorize
  post "/oauth/authorize", to: "oauth/authorizations#create"
  post "/oauth/token", to: "oauth/tokens#create"
  match "/oauth/token", to: "oauth/tokens#preflight", via: :options
  post "/oauth/register", to: "oauth/registrations#create"
  match "/oauth/register", to: "oauth/registrations#preflight", via: :options

  namespace :api do
    post "seallo/connect", to: "seallo#connect"
    post "seallo/status", to: "seallo#status"
    post "seallo/sync", to: "seallo#sync"
    post "seallo/disconnect", to: "seallo#disconnect"
    post "woocommerce/connect", to: "woocommerce#connect"
    namespace :v1 do
      resources :order_imports, only: :create
    end

    resources :orders, only: [] do
      member do
        match :confirm, via: %i[get post]
        match :cancel, via: %i[get post]
      end
    end
  end

  get "/", to: "platform_home#show", as: :platform_home, constraints: ->(request) { Store.apex_host?(request.host) }
  # Public Seallo Connect pages linked from the Shopify app listing; apex only, never tenant hosts.
  constraints ->(request) { Store.apex_host?(request.host) } do
    get "/seallo-connect", to: "seallo_connect_pages#show", as: :seallo_connect_page
    get "/seallo-connect/pricing", to: "seallo_connect_pages#pricing", as: :seallo_connect_pricing
    get "/seallo-connect/privacy", to: "seallo_connect_pages#privacy", as: :seallo_connect_privacy
    get "/seallo-connect/terms", to: "seallo_connect_pages#terms", as: :seallo_connect_terms
    get "/seallo-connect/cookies", to: "seallo_connect_pages#cookie_policy", as: :seallo_connect_cookies
    get "/seallo-connect/refunds", to: "seallo_connect_pages#refunds", as: :seallo_connect_refunds
    get "/seallo-connect/privacy-rights", to: "seallo_connect_pages#privacy_rights", as: :seallo_connect_privacy_rights
    post "/seallo-connect/privacy-rights", to: "seallo_connect_pages#create_privacy_rights"
  end
  # Seller workspace URLs, as on seallo. Each batch moves a page here; the others still open their current admin page.
  get "/dashboard", to: "admin/dashboard#show", as: :seller_dashboard
  get "/clients", to: "admin/customers#index", as: :seller_customers
  get "/integrations", to: "admin/store_connections#index", as: :seller_integrations
  get "/publicites", to: "admin/meta_ads#show", as: :seller_ads
  get "/comptabilite", to: "admin/accounting#show", as: :seller_accounting
  get "/comptabilite/export", to: "admin/accounting#export", as: :seller_accounting_export, defaults: { format: "csv" }
  post "/livraison/societes", to: "admin/delivery_accounts#create", as: :seller_delivery_accounts
  patch "/livraison/societes/:id", to: "admin/delivery_accounts#update", as: :seller_delivery_account
  post "/livraison/societes/:id/default", to: "admin/delivery_accounts#make_default", as: :seller_delivery_account_default
  delete "/livraison/societes/:id", to: "admin/delivery_accounts#destroy"
  {
    "/commandes" => "/admin/orders", "/confirmation" => "/admin/confirmations", "/mes-statistiques" => "/admin/my_stats",
    "/livraison" => "/admin/delivery", "/produits" => "/admin/products",
    "/equipe" => "/admin/staff", "/settings/profile" => "/admin/store/edit"
  }.each do |from, target|
    get from, to: redirect { |_params, request| [ target, request.query_string.presence ].compact.join("?") }
  end
  get "/signup", to: "signups#new", as: :signup
  post "/signup", to: "signups#create"
  # Seallo signup steps 2 and 3: plans (with or without an account) and payment.
  get "/abonnement", to: "subscription_setup#plans", as: :plans
  post "/abonnement", to: "subscription_setup#choose"
  get "/paiement", to: "subscription_setup#payment", as: :payment
  post "/paiement/virement", to: "subscription_setup#transfer", as: :payment_transfer
  get "/signup/thanks", to: "signups#thanks", as: :signup_thanks
  get "/signup/verify", to: "signups#verify", as: :signup_verify
  post "/signup/confirm", to: "signups#confirm", as: :signup_confirm
  post "/signup/resend", to: "signups#resend", as: :signup_resend
  get "/signup/password/new", to: "password_resets#new", as: :new_password_reset
  post "/signup/password", to: "password_resets#create", as: :password_resets
  get "/signup/password/edit", to: "password_resets#edit", as: :edit_password_reset
  patch "/signup/password", to: "password_resets#update", as: :password_reset

  root to: redirect { |_params, request|
    locale = request.cookie_jar[ApplicationController::LOCALE_COOKIE].to_s
    locale = ApplicationController.browser_locale_from(request).to_s if locale.blank?
    locale = "fr" unless Morea::Locales.available?(locale)
    "/#{locale}"
  }

  scope "/:locale", locale: /fr|en|ar/ do
    get "/", to: "home#index", as: :localized_root
    resources :collections, only: %i[index show], param: :slug
    resources :products, only: %i[show], param: :slug
    resources :pages, only: %i[show], param: :slug
    get :search, to: "searches#show", as: :search

    resource :cart, only: %i[show] do
      post :add_item
      patch :update_item
      delete :remove_item
    end

    resource :checkout, only: %i[show create]
    resource :privacy_rights, only: %i[show create], controller: "privacy_rights"
    resources :orders, only: %i[show], param: :number do
      collection do
        get :track
        post :lookup
      end
    end
  end

  namespace :admin do
    get "seallo/connect", to: "seallo_connections#show", as: :seallo_connect
    post "seallo/connect", to: "seallo_connections#create"
    get "woocommerce/connect", to: "woocommerce_connections#show", as: :woocommerce_connect
    post "woocommerce/connect", to: "woocommerce_connections#create"
    get "youcan/connect", to: "youcan_connections#show", as: :youcan_connect
    get "youcan/callback", to: "youcan_connections#callback", as: :youcan_callback
    resources :shopify_privacy_requests, only: %i[index show] do
      member do
        get :export
        post :complete
        post :retry_processing
      end
    end
    resources :privacy_rights_requests, only: %i[index show] do
      member do
        post :resolve
      end
    end
    get "manifest.webmanifest", to: "pwa#manifest", as: :pwa_manifest
    get "service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker
    resource :push_subscription, only: %i[create destroy]
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"

    root to: "dashboard#show"
    resource :subscription, only: :show
    resource :platform_agent_api, path: "platform/agent-api", only: :show, controller: "platform_agent_api" do
      post :token, action: :generate_token
      delete :token, action: :revoke_token
      delete :connections, action: :revoke_connections
    end
    get "platform", to: "platform#show", as: :platform
    resources :platform_users, path: "platform/users", except: %i[show destroy] do
      member { post "lifecycle/:lifecycle", action: :lifecycle, as: :lifecycle, constraints: { lifecycle: /suspend|reactivate|archive|restore/ } }
    end
    resources :access_requests, only: :index do
      member do
        post :approve
        post :reject
      end
    end
    resources :platform_privacy_rights_requests, only: %i[index show] do
      member do
        post :resolve
      end
    end
    resource :impersonation, only: :destroy
    resources :tenants, only: %i[index new create edit update] do
      member do
        post :enter
        post :reset
      end
      resources :invoices, only: %i[index new create show] do
        member do
          post :issue
          post :mark_paid
          post :void
        end
      end
    end
    resource :store, only: %i[edit update]
    resource :sendit_settings, only: %i[show update destroy] do
      post :refresh_cities
    end
    resource :ozon_settings, only: %i[show update] do
      post :refresh_cities
    end
    resource :ameex_settings, only: %i[show update] do
      post :refresh_cities
    end
    resources :store_connections, only: %i[index new create show update destroy]
    resource :agent_api, only: :show, controller: "agent_api" do
      post :token, action: :generate_token
      delete :token, action: :revoke_token
    end
    resource :pixels, only: %i[edit update], controller: "pixels"
    resources :products do
      resources :variants, only: %i[create edit update destroy] do
        collection do
          patch :bulk_update
        end
      end
      resources :inventory, only: %i[create]
    end
    resources :collections
    resources :discounts, except: %i[show]
    resources :users, path: "staff", except: %i[show] do
      member { post :pay }
    end
    get "my_stats", to: "my_stats#show", as: :my_stats
    get "media", to: "media#index", as: :media
    post "media/upload", to: "media#upload", as: :media_upload
    post "media/edits", to: "media#edits", as: :media_edits
    resources :confirmations, only: :index, param: :order_id do
      collection do
        get :home
        get :dashboard
        post :presence
      end
      member do
        post :claim
        post :call
        post :abandon_call
        post :finish_call
        post :release
        post :outcome
      end
    end

    resources :orders, only: %i[index show new create edit update] do
      collection do
        post :sendit_sync_all
        post :ozon_sync_all
        post :ameex_sync_all
        post :shopify_sync_all
        get :product_search
        post :quick_product
      end
      member do
        post :sendit
        post :ozon
        post :ameex
        patch :complete_import_contact
        get :sendit_label
        get :ozon_label
        patch :transition
        post :duplicate
        post :archive
        post :unarchive
        get :packing_slip
        post :comments
        patch :tags
        post :collect
        post :refund
      end
    end
    resources :customers, only: %i[index show edit update]
    resources :expenses, controller: "store_expenses", only: %i[index create destroy]
    resources :carts, only: %i[index show]

    get "delivery", to: "delivery#show", as: :delivery
    post "tiktok-ads/connect", to: "tiktok_ads#connect", as: :connect_tiktok_ads
    resource :meta_ads, path: "meta-ads", only: :show, controller: "meta_ads" do
      post :connect
      post :refresh
      patch :accounts, action: :select_accounts
      patch :product_links
      delete :connection, action: :disconnect
      get :status if Rails.env.local?
    end
    resource :advertising, only: :show, controller: "advertising" do
      post :accounts
      patch "accounts/:id", action: :update_account, as: :account
      post :campaigns
      patch "campaigns/:id", action: :update_campaign, as: :campaign
      post :performance
    end

    # Store-manager menu entries whose feature is not built yet (empty pages)
    {
      inventory: "inventory", purchases: "purchases",
      whatsapp: "whatsapp", analytics: "analytics", accounting: "accounting", workflows: "workflows",
      billing: "billing", app: "app", ai_chat: "ai-chat", help: "help"
    }.each do |feature, path|
      get path, to: "coming_soon#show", defaults: { feature: feature.to_s }, as: feature
    end

    # Online Store
    resource :online_store, only: :show, controller: "online_store"
    resources :home_sections, except: %i[show] do
      collection { patch :reorder }
      member do
        patch :move
        patch :toggle
      end
    end
    resources :themes, only: %i[index show edit update] do
      collection { post :install }
      member do
        get :preview
        match :preview_frame, via: %i[get post]
        post :publish
      end
    end
    resources :pages, except: %i[show] do
      post :preview, on: :collection
      resources :sections, controller: "page_sections", except: %i[show] do
        member do
          patch :move
          patch :toggle
        end
      end
    end
    resources :menu_items, except: %i[show] do
      member { patch :move }
    end
  end
end
