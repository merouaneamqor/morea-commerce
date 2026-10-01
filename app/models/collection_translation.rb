# frozen_string_literal: true

class CollectionTranslation < ApplicationRecord
  belongs_to :collection

  validates :locale, presence: true, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :locale, uniqueness: { scope: :collection_id }
end
