# frozen_string_literal: true

# Captures ad attribution on storefront requests and records consented funnel stages.
module StorefrontVisitTracking
  extend ActiveSupport::Concern

  included do
    after_action :capture_storefront_attribution
    after_action :record_storefront_page_visit
  end

  private

  def storefront_visit_tracker
    @storefront_visit_tracker ||= Storefront::VisitTracker.new(
      store: current_store,
      cookies: cookies,
      session: session,
      measurement_allowed: helpers.measurement_allowed?
    )
  end

  def capture_storefront_attribution
    return unless current_store
    return unless storefront_tracking_request?

    storefront_visit_tracker.capture_attribution!(request)
  end

  def record_storefront_page_visit
    return unless current_store
    return unless storefront_tracking_request?
    return unless request.get?
    return unless helpers.measurement_allowed?

    stage = storefront_page_stage
    return unless stage

    storefront_visit_tracker.record!(
      stage: stage,
      path: request.fullpath,
      product_id: (defined?(@product) && @product&.id),
      metadata: product_funnel_metadata
    )
  end

  def record_funnel_stage!(stage, product: nil, order: nil, path: nil)
    return unless current_store

    storefront_visit_tracker.capture_attribution!(request)
    storefront_visit_tracker.record!(
      stage: stage,
      path: path || request.fullpath,
      product_id: product&.id,
      order: order,
      metadata: {
        "product_slug" => product&.slug,
        "order_number" => order&.number
      }.compact
    )
  end

  def storefront_tracking_request?
    return false if is_a?(Admin::BaseController)
    return false unless current_store
    return false if Store.apex_host?(request.host)

    storefront_request? || controller_path.in?(%w[home collections products pages searches carts checkouts orders])
  end

  def storefront_page_stage
    case controller_path
    when "products" then "product_viewed"
    when "home", "collections", "pages", "searches" then "landed"
    else
      # Cart/checkout/order stages are recorded explicitly from those controllers.
      nil
    end
  end

  def product_funnel_metadata
    return {} unless defined?(@product) && @product

    { "product_slug" => @product.slug }
  end
end
