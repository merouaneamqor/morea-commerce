# frozen_string_literal: true

class PageTranslation < ApplicationRecord
  belongs_to :page

  validates :locale, presence: true, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :locale, uniqueness: { scope: :page_id }
end
