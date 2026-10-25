# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  post "webhooks/sendit/:store_slug", to: "webhooks/sendit#create", as: :sendit_webhook
  post "webhooks/store_orders/:token", to: "webhooks/store_orders#create", as: :store_orders_webhook
  post "consent/tracking", to: "consents#tracking", as: :tracking_consent

  post "/graphql", to: "graphql#execute"
  match "/mcp", to: "mcp#handle", via: %i[get post delete]

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
  get "/signup", to: "signups#new", as: :signup
  post "/signup", to: "signups#create"
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

    resource :cart, only: %i[show] do
      post :add_item
      patch :update_item
      delete :remove_item
    end

    resource :checkout, only: %i[show create]
    resources :orders, only: %i[show], param: :number do
      collection do
        get :track
        post :lookup
      end
    end
  end

  namespace :admin do
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"

    root to: "dashboard#show"
    resource :subscription, only: :show
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
    resources :tenants, only: %i[index new create edit update] do
      member do
        post :enter
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
    resources :store_connections, only: %i[index new create show update]
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
    resources :users, path: "staff", except: %i[show]
    get "media", to: "media#index", as: :media
    post "media/upload", to: "media#upload", as: :media_upload
    post "media/edits", to: "media#edits", as: :media_edits
    resources :confirmations, only: :index, param: :order_id do
      member do
        post :claim
        post :release
        post :outcome
      end
    end

    resources :orders, only: %i[index show new create edit update] do
      collection do
        post :sendit_sync_all
        get :product_search
      end
      member do
        post :sendit
        get :sendit_label
        patch :transition
        post :duplicate
        post :archive
        post :unarchive
        get :packing_slip
        post :comments
        patch :tags
      end
    end
    resources :customers, only: %i[index show edit update]
    resources :carts, only: %i[index show]

    # Store-manager menu entries whose feature is not built yet (empty pages)
    {
      inventory: "inventory", purchases: "purchases", expenses: "expenses", delivery: "delivery",
      whatsapp: "whatsapp", analytics: "analytics", accounting: "accounting", workflows: "workflows",
      billing: "billing", app: "app", ai_chat: "ai-chat", help: "help"
    }.each do |feature, path|
      get path, to: "coming_soon#show", defaults: { feature: feature.to_s }, as: feature
    end

    # Online Store
    resources :home_sections, except: %i[show] do
      member do
        patch :move
        patch :toggle
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
