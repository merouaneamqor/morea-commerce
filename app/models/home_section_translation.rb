# frozen_string_literal: true

class HomeSectionTranslation < ApplicationRecord
  belongs_to :home_section

  validates :locale, presence: true, inclusion: { in: Morea::Locales::AVAILABLE.map(&:to_s) }
  validates :locale, uniqueness: { scope: :home_section_id }
end
