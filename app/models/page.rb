# frozen_string_literal: true

# Content page or landing page at /:locale/pages/:slug
class Page < ApplicationRecord
  include Translatable

  TEMPLATES = {
    "content" => "Content page",
    "landing" => "Landing page"
  }.freeze

  belongs_to :store
  has_many :translations, class_name: "PageTranslation", dependent: :destroy, inverse_of: :page
  has_many :page_sections, dependent: :destroy

  accepts_nested_attributes_for :translations, allow_destroy: false

  translates :title, :body, :seo_title, :seo_description

  validates :slug, presence: true, uniqueness: { scope: :store_id },
                   format: { with: /\A[a-z0-9-]+\z/, message: "only lowercase letters, numbers and dashes" }
  validates :template, inclusion: { in: TEMPLATES.keys }

  before_validation :ensure_slug
  before_validation :normalize_template

  scope :published, -> { where(published: true) }
  scope :landing, -> { where(template: "landing") }
  scope :content, -> { where(template: "content") }

  def to_param
    slug
  end

  def landing?
    template == "landing"
  end

  def content?
    !landing?
  end

  def sections_for_display
    page_sections.visible.ordered.includes(:translations)
  end

  private

  def ensure_slug
    self.slug = (slug.presence || title).to_s.parameterize
  end

  def normalize_template
    self.template = template.to_s.presence || "content"
  end
end
