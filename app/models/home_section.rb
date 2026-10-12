# frozen_string_literal: true

# A block of the home page, ordered and editable from Online Store › Customize
class HomeSection < ApplicationRecord
  include SectionBlock

  KINDS = SectionBlock::KINDS
  TEXT_FIELDS = SectionBlock::TEXT_FIELDS
  SETTING_FIELDS = SectionBlock::SETTING_FIELDS

  belongs_to :store
  has_many :translations, class_name: "HomeSectionTranslation", dependent: :destroy, inverse_of: :home_section

  accepts_nested_attributes_for :translations, allow_destroy: false

  private

  def position_scope
    store.home_sections
  end
end
