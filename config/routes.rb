# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  namespace :api do
    resources :orders, only: [] do
      member do
        match :confirm, via: %i[get post]
        match :cancel, via: %i[get post]
      end
    end
  end

  root to: redirect("/fr")

  scope "/:locale", locale: /fr|en|ar/, defaults: { locale: "fr" } do
    get "/", to: "home#index", as: :localized_root
    resources :collections, only: %i[index show], param: :slug
    resources :products, only: %i[show], param: :slug

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
    resources :products do
      resources :variants, only: %i[create update destroy]
    end
    resources :collections
    resources :orders, only: %i[index show update] do
      member do
        patch :transition
      end
    end
    resources :customers, only: %i[index show]
  end
end
