# frozen_string_literal: true

# A block on a landing page, same kinds as the home page builder.
class PageSection < ApplicationRecord
  include SectionBlock

  KINDS = SectionBlock::KINDS
  TEXT_FIELDS = SectionBlock::TEXT_FIELDS
  SETTING_FIELDS = SectionBlock::SETTING_FIELDS

  belongs_to :page
  has_many :translations, class_name: "PageSectionTranslation", dependent: :destroy, inverse_of: :page_section

  accepts_nested_attributes_for :translations, allow_destroy: false

  delegate :store, to: :page

  private

  def position_scope
    page.page_sections
  end
end
