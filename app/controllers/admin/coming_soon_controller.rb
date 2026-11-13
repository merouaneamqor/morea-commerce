module Admin
  # Empty pages for store-manager menu entries whose feature is not built yet.
  class ComingSoonController < BaseController
    before_action :require_current_store!

    def show
      @entry = Admin::Menu::PLACEHOLDERS[params[:feature].to_s] or raise ActionController::RoutingError, "Not Found"
    end

    private

    def require_current_store!
      redirect_to(admin_platform_path) unless current_store
    end
  end
end
