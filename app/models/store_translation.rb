# frozen_string_literal: true

class StoreTranslation < ApplicationRecord
  belongs_to :store

  validates :locale, presence: true, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :locale, uniqueness: { scope: :store_id }
end
