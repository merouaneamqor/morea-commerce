# frozen_string_literal: true

module CatalogTools
  module OrderDesk
    ATTRS = {
      type: "object", additionalProperties: false,
      properties: {
        name: { type: "string" }, phone: { type: "string" }, phoneCountry: { type: "string" },
        city: { type: "string" }, district: { type: "string" }, address: { type: "string" },
        notes: { type: "string" }, tags: { type: "array", items: { type: "string" } },
        shippingDh: { type: "integer", minimum: 0 }, discountDh: { type: "integer", minimum: 0 },
        discountCode: { type: "string" },
        lines: { type: "array", minItems: 1, maxItems: 100, items: {
          type: "object", additionalProperties: false,
          properties: { productSlug: { type: "string" }, variantId: { type: "string" }, quantity: { type: "integer", minimum: 1, maximum: 999 } },
          required: %w[productSlug quantity]
        } }
      }
    }.freeze

    def self.write(server_context:, action:, number: nil, attrs: {}, confirm: false)
      CatalogExecutor.call(
        store: server_context.fetch(:store), include_covers: false,
        query: <<~GQL,
          mutation($action: String!, $number: String, $attrs: JSON, $confirm: Boolean!) {
            manageOrder(action: $action, number: $number, attrs: $attrs, confirm: $confirm) { order errors }
          }
        GQL
        variables: { action: action, number: number, attrs: attrs, confirm: confirm }.compact
      )
    end

    def self.read(server_context:, number:, include_contact: false)
      CatalogExecutor.call(
        store: server_context.fetch(:store), include_covers: false,
        query: "query($number: String!, $includeContact: Boolean!) { orderDesk(number: $number, includeContact: $includeContact) }",
        variables: { number: number, includeContact: include_contact }
      )
    end

    class CreateOrder < MCP::Tool
      description "Create a cash-on-delivery order using existing catalog prices. attrs needs name, phone, city, address and lines [{productSlug, variantId (required for variant products), quantity}]. Optional shippingDh, discountCode/discountDh, tags and notes. Amounts are whole currency units. Creating an order can enqueue notifications. Requires confirm: true."
      input_schema(properties: { attrs: ATTRS, confirm: { type: "boolean" } }, required: %w[attrs confirm])

      def self.call(attrs:, confirm:, server_context:)
        OrderDesk.write(server_context: server_context, action: "create", attrs: attrs, confirm: confirm)
      end
    end

    class UpdateOrder < MCP::Tool
      description "Edit an unshipped order by number. attrs uses create_order fields; omitted fields stay unchanged. Supplied lines replace all lines. Existing inventory reservations are adjusted through the admin order service. Shipping/courier locks apply. To replace a discount code with a manual amount, also pass discountCode: empty string. Requires confirm: true."
      input_schema(properties: { number: { type: "string" }, attrs: ATTRS, confirm: { type: "boolean" } }, required: %w[number attrs confirm])

      def self.call(number:, attrs:, confirm:, server_context:)
        OrderDesk.write(server_context: server_context, action: "update", number: number, attrs: attrs, confirm: confirm)
      end
    end

    class DuplicateOrder < MCP::Tool
      description "Duplicate an existing order into a new COD order using current catalog prices and the original delivery/contact details. Does not copy fulfillment status. Can enqueue notifications. Requires confirm: true."
      input_schema(properties: { number: { type: "string" }, confirm: { type: "boolean" } }, required: %w[number confirm])

      def self.call(number:, confirm:, server_context:)
        OrderDesk.write(server_context: server_context, action: "duplicate", number: number, confirm: confirm)
      end
    end

    class TransitionOrder < MCP::Tool
      description "Move an order to one of its allowedTransitions from get_order_activity. Confirming reserves inventory and may create a shipment. Courier-owned statuses cannot be overridden when Sendit is configured. Use cancel_order for cancellation. Requires confirm: true."
      input_schema(properties: { number: { type: "string" }, status: { type: "string" }, reason: { type: "string" }, confirm: { type: "boolean" } }, required: %w[number status confirm])

      def self.call(number:, status:, confirm:, server_context:, reason: nil)
        OrderDesk.write(server_context: server_context, action: "transition", number: number, attrs: { status: status, reason: reason }.compact, confirm: confirm)
      end
    end

    class SetOrderArchived < MCP::Tool
      description "Archive or unarchive an order without deleting it or changing fulfillment/inventory. Requires confirm: true."
      input_schema(properties: { number: { type: "string" }, archived: { type: "boolean" }, confirm: { type: "boolean" } }, required: %w[number archived confirm])

      def self.call(number:, archived:, confirm:, server_context:)
        OrderDesk.write(server_context: server_context, action: archived ? "archive" : "unarchive", number: number, confirm: confirm)
      end
    end

    class UpdateOrderTags < MCP::Tool
      description "Replace an order's tags with an array of strings; [] clears tags. Normalizes case and removes duplicates, recording an order event. Requires confirm: true."
      input_schema(properties: { number: { type: "string" }, tags: { type: "array", items: { type: "string" } }, confirm: { type: "boolean" } }, required: %w[number tags confirm])

      def self.call(number:, tags:, confirm:, server_context:)
        OrderDesk.write(server_context: server_context, action: "tags", number: number, attrs: { tags: tags }, confirm: confirm)
      end
    end

    class AddOrderComment < MCP::Tool
      description "Append an internal order timeline comment, 1-10000 characters. This does not message the customer. Requires confirm: true."
      input_schema(properties: { number: { type: "string" }, body: { type: "string", minLength: 1, maxLength: 10000 }, confirm: { type: "boolean" } }, required: %w[number body confirm])

      def self.call(number:, body:, confirm:, server_context:)
        OrderDesk.write(server_context: server_context, action: "comment", number: number, attrs: { body: body }, confirm: confirm)
      end
    end

    class GetOrderActivity < MCP::Tool
      description "Read order lines, amounts, tags, archive state, edit lock, allowed transitions and up to 100 most recent timeline events. Customer phone/address are omitted by default. includeContact: true returns shipping contact details only when necessary for the user's explicit task."
      input_schema(properties: { number: { type: "string" }, includeContact: { type: "boolean" } }, required: [ "number" ])

      def self.call(number:, server_context:, includeContact: false)
        OrderDesk.read(server_context: server_context, number: number, include_contact: includeContact)
      end
    end

    class GetPackingSlip < MCP::Tool
      description "Return structured packing-slip data for one order, including line items, totals, shipping contact and address. Contains customer personal data: use only for an explicit packing/delivery task. This does not generate a PDF or fulfill the order."
      input_schema(properties: { number: { type: "string" } }, required: [ "number" ])

      def self.call(number:, server_context:)
        OrderDesk.read(server_context: server_context, number: number, include_contact: true)
      end
    end

    class ManageOrderShipment < MCP::Tool
      description "Create (push) or refresh one order's Sendit parcel. Push requires a confirmed, unshipped order. Requires configured Sendit credentials and confirm: true. Use cancel_order to cancel before pickup; courier rules remain authoritative."
      input_schema(properties: { number: { type: "string" }, operation: { type: "string", enum: %w[push refresh] }, confirm: { type: "boolean" } }, required: %w[number operation confirm])

      def self.call(number:, operation:, confirm:, server_context:)
        OrderDesk.write(server_context: server_context, action: "shipment", number: number, attrs: { operation: operation }, confirm: confirm)
      end
    end

    class GetShippingLabel < MCP::Tool
      description "Return the current Sendit shipping-label URL for one store order. A parcel must already exist. The label can contain customer delivery details; use only for an explicit fulfillment task."
      input_schema(properties: { number: { type: "string" } }, required: [ "number" ])

      def self.call(number:, server_context:)
        CatalogExecutor.call(
          store: server_context.fetch(:store), include_covers: false,
          query: "query($number: String!) { shippingLabel(number: $number) }", variables: { number: number }
        )
      end
    end
  end
end
