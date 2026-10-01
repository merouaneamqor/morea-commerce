# frozen_string_literal: true

class Checkout
  include ActiveModel::Model

  attr_accessor :name, :phone, :city, :address, :notes, :cart, :store

  validates :name, :phone, :city, :address, presence: true
  validate :cart_must_have_items

  def place_order!
    validate!
    order = nil

    ActiveRecord::Base.transaction do
      customer = Customer.find_or_create_from_checkout!(
        store: store,
        name: name,
        phone: phone,
        city: city,
        address: address
      )

      order = store.orders.create!(
        customer: customer,
        customer_name: name,
        customer_phone: phone,
        customer_city: city,
        customer_address: address,
        notes: notes,
        payment_method: "cod",
        status: "new",
        currency: store.currency,
        subtotal_cents: cart.subtotal_cents,
        shipping_cents: 0,
        total_cents: cart.subtotal_cents
      )

      cart.cart_items.includes(:product, :product_variant).each do |item|
        order.order_items.create!(
          product: item.product,
          product_variant: item.product_variant,
          product_name: item.product.name,
          variant_name: item.product_variant&.display_name,
          quantity: item.quantity,
          unit_price_cents: item.unit_price_cents,
          total_cents: item.line_total_cents
        )
      end

      customer.increment!(:orders_count)
      cart.cart_items.destroy_all
    end

    OrderStatusJob.perform_later(order.id)
    order
  end

  private

  def cart_must_have_items
    errors.add(:base, "Your cart is empty") if cart.nil? || cart.empty?
  end
end
