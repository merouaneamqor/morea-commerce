# frozen_string_literal: true

ActiveAdmin.register_page "Dashboard", namespace: :superadmin do
  menu priority: 0, label: "Overview"

  content title: "Platform overview" do
    summary = Platform::DashboardSummary.new

    div class: "platform-overview" do
      para "Manage workspaces, access and subscription billing across the platform."
      div class: "platform-overview__actions" do
        text_node link_to("All workspaces", admin_tenants_path, class: "button")
        text_node link_to("New workspace", new_admin_tenant_path, class: "button")
        text_node link_to("Users and access", admin_platform_users_path, class: "button")
        text_node link_to("Access requests (#{summary.pending_requests_count})", admin_access_requests_path, class: "button")
        text_node link_to("Feature flags", superadmin_feature_flags_path, class: "button")
      end

      div class: "platform-overview__metrics" do
        [
          [ "Workspaces", summary.stores_count, "#{summary.storefronts_count} published storefronts" ],
          [ "Active users", summary.active_users_count, "Across all workspaces and platform staff" ],
          [ "Orders today", summary.orders_today_count, "Across all merchants · Casablanca time" ],
          [ "Orders in 30 days", summary.orders_30_days_count, "Includes today and all order statuses" ]
        ].each do |label, value, description|
          div class: "platform-overview__metric" do
            h3 label
            strong value.to_s
            para description
          end
        end
      end

      panel "Platform subscription billing" do
        para "Manual subscription invoices in MAD. Merchant sales are excluded."
        div class: "platform-overview__metrics" do
          [
            [ "Paid this month", summary.paid_this_month_cents, "platform-paid" ],
            [ "Outstanding issued invoices", summary.outstanding_cents, "platform-outstanding" ],
            [ "Overdue invoices (#{summary.overdue_count})", summary.overdue_cents, "platform-overdue" ]
          ].each do |label, cents, identifier|
            div class: "platform-overview__metric", id: identifier do
              h3 label
              strong helpers.number_to_currency(cents / 100.0, unit: "MAD ", precision: 2)
            end
          end
        end
      end

      panel "Overdue invoices requiring attention" do
        if summary.overdue_invoices.empty?
          para "No overdue issued invoices."
        else
          para "Showing the 10 oldest overdue invoices. Open a workspace’s invoices to review or record payment."
          table_for summary.overdue_invoices do
            column("Invoice") { |invoice| link_to invoice.number, admin_tenant_invoice_path(invoice.store, invoice) }
            column("Workspace") { |invoice| invoice.store.name }
            column("Due date") { |invoice| invoice.due_on.iso8601 }
            column("Amount") { |invoice| helpers.number_to_currency(invoice.amount_cents / 100.0, unit: "MAD ", precision: 2) }
            column("Manage") { |invoice| link_to "Review invoices", admin_tenant_invoices_path(invoice.store) }
          end
        end
      end

      panel "Newest workspaces" do
        para "The 10 most recently created workspaces."
        if summary.recent_stores.empty?
          para "No workspaces yet. Create a workspace to get started."
        else
          table_for summary.recent_stores do
            column("Workspace") { |store| link_to store.name, edit_admin_tenant_path(store) }
            column :slug
            column("Storefront") { |store| status_tag(store.storefront_enabled? ? "Published" : "Unpublished") }
            column("Subscription") { |store| status_tag store.billing_status }
            column("Period ends") { |store| store.billing_period_ends_on&.iso8601 || "—" }
            column("Manage") do |store|
              div class: "platform-overview__actions" do
                text_node link_to("Billing", admin_tenant_invoices_path(store))
                text_node helpers.button_to("Open admin", enter_admin_tenant_path(store), method: :post)
              end
            end
          end
        end
      end
    end
  end
end
