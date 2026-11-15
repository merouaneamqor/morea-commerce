# frozen_string_literal: true

# Append-only funnel step for a storefront visit. Names match StorefrontVisit stages plus abandoned.
class StorefrontFunnelEvent < ApplicationRecord
  NAMES = %w[landed product_viewed added_to_cart checkout_started abandoned ordered].freeze

  belongs_to :store
  belongs_to :storefront_visit
  belongs_to :product, optional: true

  validates :name, inclusion: { in: NAMES }

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "funnel events are append-only" }

  def readonly?
    persisted? || super
  end
end
