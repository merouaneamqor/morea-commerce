# frozen_string_literal: true

class PageSectionTranslation < ApplicationRecord
  belongs_to :page_section

  validates :locale, presence: true, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :locale, uniqueness: { scope: :page_section_id }
end
