# frozen_string_literal: true

module Admin
  # Global workspace lookup from the Super Admin topbar search.
  class PlatformSearchesController < BaseController
    layout "admin_platform"
    before_action :require_super_admin!
    before_action :enter_platform_mode

    def show
      @query = params[:q].to_s
      @stores = Platform::WorkspaceSearch.call(@query)
    end

    private

    def enter_platform_mode
      session[:admin_mode] = "platform"
    end
  end
end
