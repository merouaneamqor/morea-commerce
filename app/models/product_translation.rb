# frozen_string_literal: true

class ProductTranslation < ApplicationRecord
  belongs_to :product

  validates :locale, presence: true, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :locale, uniqueness: { scope: :product_id }
end
