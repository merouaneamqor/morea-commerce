# frozen_string_literal: true

# Public entry to the seller demo (the "Démo" button of the landing page): signs the visitor in to the fictitious Atlas Beauté workspace, read-only
# (see Admin::BaseController#block_demo_writes!). ?role=agent opens the confirmation agent's desk instead of the owner's dashboard.
class DemoController < ApplicationController
  # Other pages the demo may open directly.
  EXTRA_PAGES = %w[/admin/orders/ship_review].freeze

  rate_limit to: 30, within: 1.minute, only: :show

  def show
    store = Demo::Workspace.ensure!
    agent = params[:role].to_s == "agent"
    user = agent ? store.users.find_by!(email: Demo::Workspace::AGENT_EMAILS.first) : store.users.find_by!(email: Demo::Workspace::OWNER_EMAIL)

    reset_session
    session[:user_id] = user.id
    session[:session_version] = user.session_version
    session[:admin_mode] = "store"
    session[:login_nonce] = SecureRandom.hex(6)
    # ?to=/livraison opens the demo straight on one of the seller pages (only the known seller addresses are accepted).
    target = (ApplicationController::SELLER_PATHS + EXTRA_PAGES).include?(params[:to].to_s) ? params[:to].to_s : nil
    redirect_to(target || (agent ? admin_my_stats_path : admin_root_path))
  end
end
