# frozen_string_literal: true

# A storefront link stored as a short reference ("collection:essentials",
# "product:essential-set", "page:about", "home", "collections", "cart", "track")
# or a custom URL. Resolved to a localized path by OnlineStoreHelper#store_link_path.
module StoreLinkable
  extend ActiveSupport::Concern

  CUSTOM = "custom"

  included do
    attr_accessor :custom_url

    before_validation :apply_custom_url
  end

  def custom_link?
    link.present? && !link.to_s.match?(/\A(home|collections|cart|track|(collection|product|page):[\w-]+)\z/)
  end

  private

  def apply_custom_url
    self.link = custom_url.to_s.strip if link == CUSTOM
  end
end
