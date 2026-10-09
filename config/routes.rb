# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  post "webhooks/sendit/:store_slug", to: "webhooks/sendit#create", as: :sendit_webhook

  namespace :api do
    resources :orders, only: [] do
      member do
        match :confirm, via: %i[get post]
        match :cancel, via: %i[get post]
      end
    end
  end

  root to: redirect("/fr")

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
    resource :store, only: %i[edit update]
    resource :pixels, only: %i[edit update], controller: "pixels"
    resources :products do
      resources :variants, only: %i[create update destroy]
      resources :inventory, only: %i[create]
    end
    resources :collections
    resources :discounts, except: %i[show]
    resources :users, path: "staff", except: %i[show]
    get "media", to: "media#index", as: :media
    post "media/upload", to: "media#upload", as: :media_upload
    post "media/edits", to: "media#edits", as: :media_edits
    resources :orders, only: %i[index show update] do
      collection do
        post :sendit_sync_all
      end
      member do
        post :sendit
        get :sendit_label
        patch :transition
      end
    end
    resources :customers, only: %i[index show edit update]

    # Online Store
    resources :home_sections, except: %i[show] do
      member do
        patch :move
        patch :toggle
      end
    end
    resources :pages, except: %i[show]
    resources :menu_items, except: %i[show] do
      member { patch :move }
    end
  end
end
