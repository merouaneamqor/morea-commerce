# frozen_string_literal: true

module Admin
  class ThemesController < BaseController
    before_action :require_store_context!
    before_action :require_theme_editor_feature!
    before_action :set_theme, only: %i[show edit update publish preview]

    def index
      @themes = current_store.storefront_themes.order(created_at: :desc)
      @catalog = StorefrontThemes::Catalog.all
    end

    def install
      theme = StorefrontThemes::Install.call(store: current_store, catalog_key: params[:catalog_key])
      redirect_to admin_theme_path(theme), notice: "#{theme.name} was installed as a draft."
    rescue StorefrontThemes::Catalog::UnknownTheme
      redirect_to admin_themes_path, alert: "That theme is not available."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_themes_path, alert: error.record.errors.full_messages.to_sentence
    end

    def show; end

    def edit; end

    def update
      snapshot = params.require(:snapshot)
      snapshot = snapshot.to_unsafe_h if snapshot.respond_to?(:to_unsafe_h)
      StorefrontThemes::UpdateSnapshot.call(store: current_store, theme: @theme, snapshot: snapshot)
      render json: { saved: true, updated_at: @theme.reload.updated_at.iso8601 }
    rescue ActionController::ParameterMissing, ArgumentError, ActiveRecord::RecordInvalid => error
      render json: { saved: false, error: error.message }, status: :unprocessable_content
    end

    def publish
      unless ActiveModel::Type::Boolean.new.cast(params[:confirm])
        return redirect_to admin_theme_path(@theme), alert: "Confirm that you want to replace the current home page sections."
      end

      StorefrontThemes::Publish.call(store: current_store, theme: @theme)
      redirect_to admin_theme_path(@theme), notice: "#{@theme.name} is now published."
    rescue ActiveRecord::RecordInvalid, KeyError => error
      redirect_to admin_theme_path(@theme), alert: "The theme could not be published: #{error.message}"
    end

    def preview; end

    private

    def require_store_context!
      return if current_store

      redirect_to admin_platform_path, alert: "Choose a workspace before managing themes."
    end

    def require_theme_editor_feature!
      return if current_store&.storefront_theme_editor_enabled?

      redirect_to admin_online_store_path, alert: "The theme editor is not enabled for this workspace."
    end

    def set_theme
      @theme = current_store.storefront_themes.find(params[:id])
    end
  end
end
