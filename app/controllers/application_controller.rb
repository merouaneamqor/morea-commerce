class ApplicationController < ActionController::Base
  LOCALE_COOKIE = :morea_locale

  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :configure_session_domain
  before_action :set_current_store
  before_action :set_locale

  helper_method :current_store, :current_cart, :cart_count, :current_locale, :rtl?, :current_admin_user, :super_admin?

  def default_url_options
    return {} if is_a?(Admin::BaseController) || controller_path.start_with?("admin")

    { locale: current_locale }
  end

  private

  # Share the session across store subdomains for super admins. Leave the cookie
  # host-only on localhost — browsers reject Domain=.lvh.me there and CSRF breaks.
  def configure_session_domain
    base = Store.base_domain
    host = request.host
    if host == base || host == "www.#{base}" || host.end_with?(".#{base}")
      request.session_options[:domain] = ".#{base}"
    else
      request.session_options[:domain] = nil
    end
  end

  def set_current_store
    if Store.apex_host?(request.host)
      Current.store = nil
      return if apex_request_allowed?

      default = Store.find_by(slug: ENV.fetch("DEFAULT_STORE_SLUG", "morea"))
      if default
        return redirect_to("#{default.origin}#{request.fullpath}", allow_other_host: true, status: :moved_permanently)
      end

      return render template: "stores/missing", layout: "bare", status: :not_found
    end

    Current.store = Store.find_by_host(request.host)
    return if Current.store

    render template: "stores/missing", layout: "bare", status: :not_found
  end

  # Apex (ollazen.com / www) hosts the SaaS platform, not a storefront.
  def apex_request_allowed?
    path = request.path
    path == "/up" ||
      path.start_with?("/admin") ||
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

  def self.browser_locale_from(request)
    header = request.env["HTTP_ACCEPT_LANGUAGE"].to_s.downcase
    return :ar if header.match?(/\bar(?:[-_;,]|$)/)
    return :en if header.match?(/\ben(?:[-_;,]|$)/)

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
  def current_admin_user
    return @current_admin_user if defined?(@current_admin_user)
    return @current_admin_user = nil unless session[:user_id]

    @current_admin_user = current_store&.users&.find_by(id: session[:user_id]) ||
      User.super_admins.find_by(id: session[:user_id])
  end

  def super_admin?
    current_admin_user&.super_admin?
  end

  def normalize_locale(locale)
    locale = locale.to_sym
    Morea::Locales.available?(locale) ? locale : Morea::Locales::DEFAULT
  end

  def browser_locale_preference
    self.class.browser_locale_from(request)
  end

  def persist_locale_cookie(locale)
    cookies[LOCALE_COOKIE] = {
      value: locale.to_s,
      expires: 1.year.from_now,
      same_site: :lax,
      secure: !Rails.env.local?
    }
  end
end
