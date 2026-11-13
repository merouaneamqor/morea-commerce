# frozen_string_literal: true

module Orders
  # Contact-only repair: imported line snapshots, amounts and provider identity
  # remain immutable. Lock like intake/privacy: connection, workspace, order.
  class CompleteImportedContact
    class Error < StandardError; end
    FIELDS = %i[name phone city address district].freeze

    def initialize(store:, user:)
      @store, @user = store, user
    end

    def call(order:, attrs:)
      authorize!
      order = @store.orders.find(order.id)
      connection = order.store_connection
      raise Error, I18n.t("import_contact.blocked") unless connection&.shopify_app == "seallo_connect"
      contact = normalize(attrs)
      connection.with_lock do
        @store.with_lock do
          order.with_lock do
            raise Error, I18n.t("import_contact.blocked") unless order.contact_review_required? && order.status == "new" && order.sendit_code.blank?

            customer = @store.customers.find_or_initialize_by(phone: contact.fetch(:phone))
            customer.assign_attributes(name: contact.fetch(:name), city: contact.fetch(:city))
            customer.save!
            previous_customer = order.customer
            order.update!(customer: customer, customer_name: contact[:name], customer_phone: contact[:phone],
              customer_city: contact[:city], customer_address: contact[:address], customer_district: contact[:district],
              import_contact_issues: [])
            if previous_customer&.id != customer.id
              previous_customer.decrement!(:orders_count) if previous_customer && previous_customer.orders_count.positive?
              customer.increment!(:orders_count)
            end
            order.record_event!("edited", body: "Imported order contact details completed", user: @user)
          end
        end
      end
      order
    rescue ActiveRecord::RecordInvalid => error
      raise Error, error.record.errors.full_messages.to_sentence
    end

    private

    def authorize!
      raise ActiveRecord::RecordNotFound unless @user.is_a?(User) && @user.persisted?
      @user.reload
      unless @user.active? && (@user.super_admin? || (@user.store_id == @store.id && @user.admin?))
        raise ActiveRecord::RecordNotFound
      end
    end

    def normalize(attrs)
      raise Error, I18n.t("import_contact.blocked") unless attrs.is_a?(Hash)
      contact = attrs.symbolize_keys.slice(*FIELDS)
      contact.transform_values! do |value|
        raise Error, I18n.t("import_contact.blocked") unless value.nil? || value.is_a?(String)
        value&.strip&.presence
      end
      if contact.values.any? { |value| value && value.length > 255 } || %i[name phone city address].any? { |field| contact[field].blank? }
        raise Error, I18n.t("import_contact.blocked")
      end
      contact[:phone] = contact.fetch(:phone).gsub(/[^\d+]/, "")
      raise Error, I18n.t("import_contact.blocked") unless contact[:phone].match?(/\A\+?\d{8,15}\z/)
      contact
    end
  end
end
