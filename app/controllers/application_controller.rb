class ApplicationController < ActionController::Base
  LOCALE_COOKIE = :morea_locale
  # Default signed-in lifetime. "Remember me" stretches this on every cookie rewrite.
  SESSION_TTL = 30.days
  REMEMBER_TTL = 90.days

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :configure_session_cookie
  before_action :set_current_store
  before_action :set_locale

  helper_method :current_store, :current_cart, :cart_count, :current_locale, :rtl?, :current_admin_user, :admin_entry_path, :super_admin?, :impersonating?, :store_billing_past_due?

  def authenticate_super_admin!
    return if current_admin_user&.super_admin?

    redirect_to(current_admin_user ? admin_root_path : admin_login_path, alert: "Super admin access required.")
  end

  def default_url_options
    return {} if is_a?(Admin::BaseController) || controller_path.start_with?("admin", "superadmin")

    { locale: current_locale }
  end

  private

  # Share the session across store subdomains for super admins. Leave the cookie
  # host-only on localhost — browsers reject Domain=.lvh.me there and CSRF breaks.
  # Re-apply expire_after on every request so flash/session writes keep Max-Age
  # instead of collapsing back to a browser-session cookie.
  def configure_session_cookie
    base = Store.base_domain
    host = request.host
    if host == base || host == "www.#{base}" || host.end_with?(".#{base}")
      request.session_options[:domain] = ".#{base}"
    else
      request.session_options[:domain] = nil
    end
    request.session_options[:expire_after] = session[:remember_admin] ? REMEMBER_TTL : SESSION_TTL
  end

  def set_current_store
    if Store.apex_host?(request.host)
      # Merchants use their authenticated membership on the shared admin host.
      # Super admins may select a workspace through the authorized enter action.
      Current.store = apex_admin_workspace
      return if apex_request_allowed?

      # The apex never serves a storefront; stores live on their own subdomains.
      return render template: "stores/missing", layout: "bare", status: :not_found
    end

    Current.store = Store.find_by_host(request.host)
    if Current.store
      return unless !Current.store.storefront_enabled? && storefront_request?

      return render template: "stores/missing", layout: "bare", status: :not_found
    end

    render template: "stores/missing", layout: "bare", status: :not_found
  end

  def apex_admin_workspace
    return unless (request.path.start_with?("/admin") || seller_path?) && session[:user_id]

    user = User.active.find_by(id: session[:user_id])
    return unless user && session[:session_version].to_i == user.session_version

    if user.super_admin?
      Store.find_by(id: session[:admin_store_id]) if session[:admin_mode] == "store"
    elsif user.admin? || user.confirmation_agent?
      user.store
    end
  end

  # Seller workspace pages (as on seallo) are served on the shared admin host as well as on tenant hosts.
  SELLER_PATHS = %w[/dashboard /commandes /confirmation /mes-statistiques /clients /livraison /produits /themes /publicites /equipe /integrations /comptabilite /settings].freeze

  def seller_path?
    SELLER_PATHS.any? { |path| request.path == path || request.path.start_with?("#{path}/") }
  end

  def storefront_request?
    request.path == "/" || request.path == "/sitemap.xml" || request.path.match?(%r{\A/(?:fr|en|es|ar)(?:/|\z)}) || request.path == "/consent/tracking"
  end

  # Apex (seallo.ma / www) hosts the SaaS platform, not a storefront.
  def apex_request_allowed?
    path = request.path
    path == "/" ||
      path == "/demo" ||
      path == "/sitemap.xml" ||
      path.start_with?("/signup") ||
      path.start_with?("/auth/meta/") ||
      path == "/abonnement" ||
      path.start_with?("/paiement") ||
      seller_path? ||
      path == "/seallo-connect" ||
      path.start_with?("/seallo-connect/") ||
      path == "/consent/tracking" ||
      path == "/up" ||
      path == "/graphql" ||
      path == "/mcp" ||
      path.start_with?("/platform/oauth/") ||
      path.start_with?("/admin") ||
      path.start_with?("/superadmin") ||
      path.start_with?("/oauth") ||
      path.start_with?("/.well-known") ||
      path.start_with?("/webhooks") ||
      path.start_with?("/api")
  end

  def set_locale
    locale =
      if params[:locale].present?
        normalize_locale(params[:locale])
      else
        cookies[LOCALE_COOKIE].presence || browser_locale_preference
      end
    locale = normalize_locale(locale)
    persist_locale_cookie(locale) if params[:locale].present? || cookies[LOCALE_COOKIE].blank?
    I18n.locale = locale
  end

  # French is the default for first-time visitors whatever the browser's language;
  # an explicit ?locale= or the saved language cookie still wins.
  def self.browser_locale_from(_request)
    Morea::Locales::DEFAULT
  end

  def current_locale
    I18n.locale
  end

  def rtl?
    Morea::Locales.rtl?(current_locale)
  end

  def current_store
    Current.store
  end

  def current_cart
    return @current_cart if defined?(@current_cart)
    return @current_cart = nil unless current_store

    @current_cart = current_store.carts.find_by(token: session[:cart_token])
    if @current_cart.nil?
      @current_cart = current_store.carts.create!
      session[:cart_token] = @current_cart.token
    end
    @current_cart
  end

  def cart_count
    current_cart&.item_count.to_i
  end

  def require_store!
    redirect_to localized_root_path, alert: t("store.preparing") unless current_store
  end

  # Store staff for this host, or a platform super admin (any host).
  # On the apex marketing home, Current.store is unset, so staff are resolved from
  # the session directly so the navbar can show signed-in actions.
  def current_admin_user
    return @current_admin_user if defined?(@current_admin_user)
    return @current_admin_user = nil unless session[:user_id]
    return @current_admin_user = nil if session[:impersonator_id].present? && !impersonator_still_valid?

    user = resolve_session_admin_user
    @current_admin_user = user if user && session[:session_version].to_i == user.session_version
  end

  # Destination after landing-page "Dashboard" / post-login entry.
  # Plain admin paths (no public locale query) so the navbar matches post-login redirects.
  def admin_entry_path(user = current_admin_user)
    return admin_login_path(locale: I18n.locale) unless user
    return "/admin/platform" if user.super_admin?
    return "/admin/confirmations/home" if user.confirmation_agent?

    "/admin"
  end

  def super_admin?
    current_admin_user&.super_admin?
  end

  def impersonating?
    session[:impersonator_id].present? && current_admin_user.present?
  end

  def impersonator_still_valid?
    impersonator = User.super_admins.active.find_by(id: session[:impersonator_id])
    impersonator && session[:impersonator_session_version].to_i == impersonator.session_version
  end

  def store_billing_past_due?
    current_store&.billing_past_due?
  end

  def resolve_session_admin_user
    if current_store
      return current_store.users.active.find_by(id: session[:user_id]) ||
        User.super_admins.active.find_by(id: session[:user_id])
    end

    return unless Store.apex_host?(request.host)

    user = User.active.find_by(id: session[:user_id])
    return unless user&.can_sign_in?
    return user if user.super_admin?
    user if user.store_id.present? && (user.admin? || user.confirmation_agent?)
  end

  def normalize_locale(locale)
    locale = locale.to_sym
    Morea::Locales.available?(locale) ? locale : Morea::Locales::DEFAULT
  end

  def browser_locale_preference
    self.class.browser_locale_from(request)
  end

  def persist_locale_cookie(locale)
    base = Store.base_domain
    shared = request.host == base || request.host.end_with?(".#{base}")
    cookies[LOCALE_COOKIE] = {
      value: locale.to_s,
      expires: 1.year.from_now,
      same_site: :lax,
      secure: !Rails.env.local?,
      # Same language on the home page, the sign-in page and every workspace subdomain.
      domain: (".#{base}" if shared)
    }.compact
  end
end
