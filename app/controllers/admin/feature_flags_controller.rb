# frozen_string_literal: true

module Admin
  class FeatureFlagsController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode
    before_action :set_store, only: :update

    def index
      @stores = Store.order(:name)
    end

    def update
      @store.update!(feature_flag_params)
      redirect_to admin_feature_flags_path, notice: "Feature flags updated for #{@store.name}."
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end

    def set_store
      @store = Store.find(params[:id])
    end

    def feature_flag_params
      params.require(:feature_flag).permit(:storefront_theme_editor_enabled)
    end
  end
end
