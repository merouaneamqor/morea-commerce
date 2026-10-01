class Collection < ApplicationRecord
  include Translatable

  belongs_to :store
  has_many :collection_products, -> { order(:position) }, dependent: :destroy
  has_many :products, through: :collection_products
  has_many :translations, class_name: "CollectionTranslation", dependent: :destroy, inverse_of: :collection

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :name, :subtitle, :description

  validates :name, :slug, presence: true
  validates :slug, uniqueness: { scope: :store_id }

  before_validation :ensure_slug, on: :create

  scope :published, -> { where(published: true).order(:position, :name) }

  def to_param
    slug
  end

  private

  def ensure_slug
    self.slug = name.to_s.parameterize if slug.blank?
  end
end
