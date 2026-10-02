# frozen_string_literal: true

# Content page served at /:locale/pages/:slug (About, Shipping, Returns…)
class Page < ApplicationRecord
  include Translatable

  belongs_to :store
  has_many :translations, class_name: "PageTranslation", dependent: :destroy, inverse_of: :page

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :title, :body, :seo_title, :seo_description

  validates :slug, presence: true, uniqueness: { scope: :store_id },
                   format: { with: /\A[a-z0-9-]+\z/, message: "only lowercase letters, numbers and dashes" }

  before_validation :ensure_slug

  scope :published, -> { where(published: true) }

  def to_param
    slug
  end

  private

  def ensure_slug
    self.slug = (slug.presence || title).to_s.parameterize
  end
end
