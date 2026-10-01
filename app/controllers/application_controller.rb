class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  stale_when_importmap_changes

  before_action :set_locale

  helper_method :current_store, :current_cart, :cart_count, :current_locale, :rtl?

  def default_url_options
    return {} if is_a?(Admin::BaseController) || controller_path.start_with?("admin")

    { locale: current_locale }
  end

  private

  def set_locale
    locale = params[:locale].presence || Morea::Locales::DEFAULT
    locale = Morea::Locales::DEFAULT unless Morea::Locales.available?(locale)
    I18n.locale = locale
  end

  def current_locale
    I18n.locale
  end

  def rtl?
    Morea::Locales.rtl?(current_locale)
  end

  def current_store
    @current_store ||= Store.current
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
end
