module Admin
  # Store-manager sidebar (issue #104). Entries without a built feature use
  # `placeholder: true` and render an empty page until the feature ships.
  module Menu
    Entry = Struct.new(:key, :route, :icon, :controllers, :placeholder, keyword_init: true) do
      def placeholder? = placeholder
    end

    def self.entry(key, route, icon, controllers: [], placeholder: false)
      Entry.new(key: key, route: route, icon: icon, controllers: Array(controllers) + [ (placeholder ? "coming_soon" : nil) ].compact, placeholder: placeholder)
    end

    GROUPS = [
      [ nil, [
        entry(:dashboard, :admin_root_path, :home, controllers: "dashboard"),
        entry(:orders, :admin_orders_path, :orders, controllers: %w[orders carts]),
        entry(:customers, :admin_customers_path, :customers, controllers: "customers"),
        entry(:products, :admin_products_path, :products, controllers: %w[products variants inventory collections discounts media])
      ] ],
      [ :operations, [
        entry(:inventory, :admin_inventory_path, :inventory, placeholder: true),
        entry(:purchases, :admin_purchases_path, :purchases, placeholder: true),
        entry(:expenses, :admin_expenses_path, :expenses, controllers: "store_expenses"),
        entry(:delivery, :admin_delivery_path, :delivery, controllers: "delivery"),
        entry(:call_center, :admin_confirmations_path, :call_center, controllers: "confirmations")
      ] ],
      [ :channels, [
        entry(:stores, :admin_store_connections_path, :external, controllers: "store_connections"),
        entry(:advertising, :admin_advertising_path, :advertising, controllers: %w[advertising pixels]),
        entry(:whatsapp, :admin_whatsapp_path, :whatsapp, placeholder: true)
      ] ],
      [ :insights, [
        entry(:analytics, :admin_analytics_path, :analytics, placeholder: true),
        entry(:accounting, :admin_accounting_path, :accounting, placeholder: true)
      ] ],
      [ :team, [
        entry(:agents, :admin_users_path, :staff, controllers: "users"),
        entry(:workflows, :admin_workflows_path, :workflows, placeholder: true)
      ] ],
      [ :account, [
        entry(:billing, :admin_subscription_path, :billing, controllers: "subscriptions"),
        entry(:app, :admin_app_path, :app, placeholder: true),
        entry(:ai_chat, :admin_ai_chat_path, :ai_chat, placeholder: true),
        entry(:help, :admin_help_path, :help, placeholder: true)
      ] ]
    ].freeze

    PLACEHOLDERS = GROUPS.flat_map { |_, entries| entries }.select(&:placeholder?).index_by { |e| e.key.to_s }.freeze
  end
end
