module MerchantDashboardHelper
  def dashboard_time(value)
    l(value.in_time_zone(Admin::DashboardSummary::ZONE), format: t("dashboard.timestamp_format"))
  end

  def dashboard_primary_action(dashboard)
    if dashboard.has_products
      [ t("dashboard.create_order"), new_admin_order_path ]
    elsif dashboard.store.storefront_enabled?
      [ t("dashboard.add_product"), new_admin_product_path ]
    elsif dashboard.connections_count.zero?
      [ t("connections.add"), new_admin_store_connection_path ]
    else
      [ t("dashboard.manage_channels"), admin_store_connections_path ]
    end
  end

  def dashboard_order_values(dashboard)
    values = dashboard.order_values.presence || { dashboard.store.currency => 0 }
    safe_join(values.sort.map { |currency, cents| dashboard_money(cents, currency) }, tag.br)
  end

  def dashboard_money(cents, currency = "MAD")
    number_to_currency(BigDecimal(cents.to_i.to_s) / 100, unit: currency == "DH" ? "MAD" : currency, format: "%n %u", precision: 2)
  end

  def dashboard_order_source(order)
    order.external_order_receipt&.store_connection&.name || order.order_imports.first&.source&.humanize || t("dashboard.direct_source")
  end

  def dashboard_stock_label(product)
    variants = product.product_variants.select(&:active?)
    if variants.any?
      t("dashboard.variant_stock", count: variants.map(&:stock).min)
    else
      t("dashboard.stock_left", count: product.stock)
    end
  end

  def dashboard_connection_tone(connection)
    return "neutral" unless connection.active?
    return "critical" if connection.last_error_code.present?

    connection.verified_at? ? "success" : "attention"
  end
end
