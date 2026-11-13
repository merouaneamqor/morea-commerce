# frozen_string_literal: true

module Admin
  class ThemesController < BaseController
    layout ->(controller) { controller.action_name == "edit" ? "theme_editor" : "admin" }

    before_action :require_store_context!
    before_action :require_theme_editor_feature!, except: %i[index open]
    before_action :set_theme, only: %i[show edit update publish preview preview_frame duplicate upload_image]

    def open
      theme = current_store.storefront_themes.draft.order(updated_at: :desc).first if current_store.storefront_theme_editor_enabled?
      redirect_to(theme ? edit_admin_theme_path(theme) : admin_themes_path)
    end

    def index
      @theme_editor_enabled = current_store.storefront_theme_editor_enabled?
      return unless @theme_editor_enabled

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

    def create_from_live
      theme = StorefrontThemes::CreateFromLive.call(store: current_store)
      redirect_to edit_admin_theme_path(theme), notice: "#{theme.name} was created from the live home page."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_themes_path, alert: error.record.errors.full_messages.to_sentence
    end

    def show
      @draft_sections = Array(@theme.snapshot&.dig("sections"))
      @live_sections = current_store.home_sections.ordered.to_a
      @draft_kinds = @draft_sections.map { |section| section["kind"] }.compact
      @live_kinds = @live_sections.map(&:kind)
    end

    def edit; end

    def upload_image
      if @theme.published?
        return render json: { error: "Only draft themes can be edited." }, status: :unprocessable_content
      end

      file = params[:image]
      unless file.respond_to?(:content_type) && file.content_type.to_s.in?(%w[image/jpeg image/png image/gif image/webp])
        return render json: { error: "Choose a JPEG, PNG, GIF, or WebP image." }, status: :unprocessable_content
      end
      if file.size > 8.megabytes
        return render json: { error: "Image must be 8 MB or smaller." }, status: :unprocessable_content
      end

      @theme.images.attach(file)
      attachment = @theme.images.attachments.includes(:blob).order(:id).last
      render json: { url: MediaUrl.for(attachment, store: current_store) }
    end

    def update
      snapshot = params.require(:snapshot)
      snapshot = snapshot.to_unsafe_h if snapshot.respond_to?(:to_unsafe_h)
      StorefrontThemes::UpdateSnapshot.call(store: current_store, theme: @theme, snapshot: snapshot)
      render json: { saved: true, updated_at: @theme.reload.updated_at.iso8601 }
    rescue ActionController::ParameterMissing, ArgumentError, ActiveRecord::RecordInvalid => error
      render json: { saved: false, error: error.message }, status: :unprocessable_content
    end

    def duplicate
      copy = StorefrontThemes::Duplicate.call(store: current_store, theme: @theme)
      redirect_to edit_admin_theme_path(copy), notice: "#{copy.name} was created as a draft."
    rescue StorefrontThemes::Duplicate::StoreMismatch
      redirect_to admin_themes_path, alert: "That theme is not available."
    rescue ActiveRecord::RecordInvalid => error
      redirect_to admin_theme_path(@theme), alert: error.record.errors.full_messages.to_sentence
    end

    def publish
      unless ActiveModel::Type::Boolean.new.cast(params[:confirm])
        return redirect_to admin_theme_path(@theme), alert: "Confirm that you want to replace the current home page sections."
      end

      StorefrontThemes::Publish.call(store: current_store, theme: @theme)
      redirect_to admin_theme_path(@theme), notice: "#{@theme.name} is now published."
    rescue StorefrontThemes::Publish::EmptyHome => error
      redirect_to admin_theme_path(@theme), alert: error.message
    rescue ActiveRecord::RecordInvalid, KeyError => error
      redirect_to admin_theme_path(@theme), alert: "The theme could not be published: #{error.message}"
    end

    def preview
      load_preview_sections!
    end

    def preview_frame
      load_preview_sections!
      render :preview_frame, formats: [ :html ], layout: false
    end

    def default_url_options
      return { locale: (@preview_locale || I18n.locale) } if action_name.in?(%w[preview preview_frame])

      {}
    end

    private

    def load_preview_sections!
      @preview_locale = normalize_locale(params[:locale].presence || I18n.locale)
      I18n.locale = @preview_locale
      snapshot = preview_snapshot_param || @theme.snapshot
      @sections = StorefrontThemes::PreviewSections.call(store: current_store, snapshot: snapshot)
      @selected_index = params[:selected_index].presence&.to_i
    end

    def preview_snapshot_param
      return unless params.key?(:snapshot)

      snapshot = params[:snapshot]
      snapshot = snapshot.to_unsafe_h if snapshot.respond_to?(:to_unsafe_h)
      snapshot
    end


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
