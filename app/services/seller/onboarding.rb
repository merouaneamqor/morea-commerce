# frozen_string_literal: true

module Seller
  # First-run checklist for a merchant workspace. Steps adapt to storefront vs
  # external-only mode and stay read-only: completing work elsewhere clears them.
  class Onboarding
    Step = Data.define(:key, :done, :title_key, :help_key, :path, :cta_key, :tour_target)

    def initialize(store:)
      raise ArgumentError, "A persisted workspace is required" unless store.is_a?(Store) && store.persisted?

      @store = store
    end

    def visible?
      !complete?
    end

    def complete?
      steps.all?(&:done)
    end

    def done_count
      steps.count(&:done)
    end

    def total_count
      steps.size
    end

    def progress_percent
      return 100 if total_count.zero?

      ((done_count.to_f / total_count) * 100).round
    end

    def steps
      @steps ||= build_steps
    end

    def to_h
      {
        complete: complete?,
        done_count: done_count,
        total_count: total_count,
        progress_percent: progress_percent,
        storefront_enabled: @store.storefront_enabled?,
        steps: steps.map { |step| step.to_h }
      }
    end

    private

    def build_steps
      list = []
      list << source_step
      list << products_step if @store.storefront_enabled?
      list << carrier_step
      list << first_order_step
      list << confirm_step if has_orders?
      list
    end

    def source_step
      done = has_connection? || @store.storefront_enabled?
      Step.new(
        key: "source",
        done: done,
        title_key: "dashboard.setup.connect",
        help_key: "dashboard.setup.connect_help",
        path: "/integrations",
        cta_key: "dashboard.onboarding.cta_connect",
        tour_target: "integrations"
      )
    end

    def products_step
      done = has_products?
      Step.new(
        key: "products",
        done: done,
        title_key: done ? "dashboard.setup.present_storefront" : "dashboard.setup.add_products",
        help_key: "dashboard.setup.storefront_help",
        path: done ? "/admin/online_store" : "/admin/products/new",
        cta_key: done ? "dashboard.customize" : "dashboard.add_product",
        tour_target: done ? "online_store" : "products"
      )
    end

    def carrier_step
      Step.new(
        key: "carrier",
        done: has_carrier?,
        title_key: "dashboard.onboarding.carrier",
        help_key: "dashboard.onboarding.carrier_help",
        path: "/livraison",
        cta_key: "dashboard.onboarding.cta_carrier",
        tour_target: "delivery"
      )
    end

    def first_order_step
      Step.new(
        key: "first_order",
        done: has_orders?,
        title_key: "dashboard.setup.first_order",
        help_key: "dashboard.setup.first_order_help",
        path: "/commandes",
        cta_key: "dashboard.onboarding.cta_orders",
        tour_target: "orders"
      )
    end

    def confirm_step
      Step.new(
        key: "confirm",
        done: has_confirmed_work?,
        title_key: "dashboard.onboarding.confirm",
        help_key: "dashboard.onboarding.confirm_help",
        path: "/confirmation",
        cta_key: "dashboard.onboarding.cta_confirm",
        tour_target: "confirmation"
      )
    end

    def has_connection?
      return @has_connection if defined?(@has_connection)

      @has_connection = @store.store_connections.exists?
    end

    def has_products?
      return @has_products if defined?(@has_products)

      @has_products = @store.products.active.exists?
    end

    def has_carrier?
      return @has_carrier if defined?(@has_carrier)

      @has_carrier = @store.delivery_accounts.where(is_active: true).exists? || @store.sendit_configured?
    end

    def has_orders?
      return @has_orders if defined?(@has_orders)

      @has_orders = @store.orders.exists?
    end

    def has_confirmed_work?
      return @has_confirmed_work if defined?(@has_confirmed_work)

      @has_confirmed_work = @store.orders.where.not(status: "new").exists?
    end
  end
end
