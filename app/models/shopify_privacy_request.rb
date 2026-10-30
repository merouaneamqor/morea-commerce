# frozen_string_literal: true

class ShopifyPrivacyRequest < ApplicationRecord
  TERMINAL_STATUSES = %w[delivered cancelled returned].freeze
  belongs_to :store_connection, optional: true

  validates :event_key, presence: true
  validates :topic, inclusion: { in: %w[customers/data_request customers/redact shop/redact] }
  validates :status, inclusion: { in: %w[pending needs_review completed] }

  def identifiers
    return {} if identifiers_ciphertext.blank?

    encryptor.decrypt_and_verify(identifiers_ciphertext, purpose: "shopify-privacy-identifiers")
  end

  def identifiers=(value)
    self.identifiers_ciphertext = value.present? ? encryptor.encrypt_and_sign(value, purpose: "shopify-privacy-identifiers") : nil
  end

  # Call only after resolving this request through the authenticated workspace.
  # Exports are generated on demand and never written to disk or a public URL.
  def export_data
    raise ArgumentError, "Only customer data requests can be exported" unless topic == "customers/data_request"

    orders = requested_orders.includes(:order_items, :order_events, order_confirmation: :confirmation_attempts)
    { request_id: identifiers["request_id"], customer_id: identifiers["customer_id"],
      orders: orders.map do |order|
        { order: order.attributes,
          items: order.order_items.map(&:attributes),
          events: order.order_events.map { |event| event.attributes.except("user_id") },
          confirmation: order.order_confirmation&.attributes&.except("assigned_user_id"),
          attempts: order.order_confirmation&.confirmation_attempts&.map { |attempt| attempt.attributes.except("user_id", "actor_label") } }
      end }
  end

  # A completed data request means the merchant has delivered the secure export.
  # Redaction completion is automatic only when no retained records need review.
  def complete!
    with_lock do
        return if status == "completed"
        unless topic == "customers/data_request" && status == "needs_review"
          raise ArgumentError, "Process this request and resolve retained records before completing it"
        end

      update!(status: "completed", error_code: nil, processed_at: Time.current, identifiers: nil)
    end
  end

  def process!
    with_lock do
      return if status == "completed"
      unless store_connection
        update!(status: "completed", processed_at: Time.current, identifiers: nil)
        return
      end
      if topic == "customers/data_request"
        update!(status: "needs_review", error_code: "secure_response_required", processed_at: Time.current)
        return
      end

      connection = store_connection
      connection.with_lock do
        # Match the intake lock order: connection then workspace. Intake cannot
        # add another order to a profile during its privacy assessment.
        connection.store.with_lock do
          if topic == "shop/redact"
            connection.update!(active: false, shopify_access_token: nil, shopify_refresh_token: nil,
              shopify_access_token_expires_at: nil, shopify_refresh_token_expires_at: nil,
              shopify_api_verified_at: nil, shopify_granted_scopes: [])
          end
          retained = false
          scope = requested_orders
          selected_ids = scope.select(:id)
          scope.find_each do |order|
            order.with_lock do
              unless TERMINAL_STATUSES.include?(order.status)
                retained = true
                next
              end

              redact_order!(order)
              customer = order.customer
              # Shared profiles belong to the merchant's other order histories.
              # Never anonymize another provider's or an active shipment's data.
              if customer.orders.where.not(id: selected_ids).exists? ||
                  customer.orders.where(id: selected_ids).where.not(status: TERMINAL_STATUSES).exists?
                retained = true
              else
                customer.update_columns(name: "Redacted", phone: "redacted-#{customer.id}", email: nil, city: nil, updated_at: Time.current)
                customer.addresses.delete_all
              end
            end
          end
          update!(status: retained ? "needs_review" : "completed", error_code: retained ? "retained_business_records" : nil,
            processed_at: Time.current, identifiers: retained ? identifiers : nil)
        end
      end
    end
  end

  private

  def requested_orders
    return Order.none unless store_connection

    receipts = store_connection.external_order_receipts.where(status: "accepted")
    receipts = receipts.where(external_id: identifiers.fetch("order_ids", [])) unless topic == "shop/redact"
    store_connection.store.orders.where(id: receipts.select(:order_id))
  end

  def redact_order!(order)
    # Preserve financial amounts, inventory, provider identity and shipping state.
    # Free text may contain copied contact details, so erase it with snapshots.
    order.update_columns(customer_name: "Redacted", customer_phone: "redacted-#{order.id}", customer_city: "Redacted",
      customer_address: "Redacted", customer_district: nil, notes: nil, cancel_reason: nil,
      sendit_district_name: nil, sendit_message: nil, sendit_error: nil, tags: nil, updated_at: Time.current)
    order.order_events.update_all(body: "[Redacted]")
    order.order_confirmation&.confirmation_attempts&.update_all(notes: nil)
  end

  def encryptor
    key = Rails.application.key_generator.generate_key("morea-shopify-privacy-v1", 32)
    ActiveSupport::MessageEncryptor.new(key, cipher: "aes-256-gcm", serializer: JSON)
  end
end
