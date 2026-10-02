# frozen_string_literal: true

class MenuItemTranslation < ApplicationRecord
  belongs_to :menu_item

  validates :locale, presence: true, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :locale, uniqueness: { scope: :menu_item_id }
end
