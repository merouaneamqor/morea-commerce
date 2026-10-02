# frozen_string_literal: true

# A link in the storefront header or footer menu (Online Store › Navigation)
class MenuItem < ApplicationRecord
  include Translatable
  include StoreLinkable
  include Positioned

  MENUS = { "header" => "Main menu", "footer" => "Footer menu" }.freeze

  belongs_to :store
  has_many :translations, class_name: "MenuItemTranslation", dependent: :destroy, inverse_of: :menu_item

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :label

  validates :menu, inclusion: { in: MENUS.keys }
  validates :link, presence: true

  scope :ordered, -> { order(:position, :id) }
  scope :in_menu, ->(menu) { where(menu: menu).ordered }

  private

  def position_scope
    store.menu_items.where(menu: menu)
  end
end
