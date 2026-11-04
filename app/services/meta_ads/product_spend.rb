# frozen_string_literal: true

module MetaAds
  # Ad spend per product over a range of days, in the store's currency, for the profit figures.
  # Each ad-level row goes to the product linked to its ad, else its ad set, else its campaign. Spend with no
  # link is reported separately rather than spread over products. Rows that could not be converted yet are
  # counted and left out of the totals.
  #
  #   profit of a product = sales - product cost - delivery fees - by_product[product_id]
  class ProductSpend
    Result = Struct.new(:by_product, :unassigned, :unconverted_rows, :currency, keyword_init: true)

    def self.call(store:, range:)
      rows = DailyInsight.where(store_id: store.id, level: "ad", date: range)
      links = ProductLink.where(store_id: store.id).pluck(:object_type, :meta_id, :product_id).to_h { |type, meta_id, product_id| [ [ type, meta_id ], product_id ] }
      by_product = Hash.new { |hash, key| hash[key] = BigDecimal(0) }
      unassigned = BigDecimal(0)
      rows.where.not(spend_display: nil).pluck(:meta_ad_id, :meta_adset_id, :meta_campaign_id, :spend_display).each do |ad_id, adset_id, campaign_id, spend|
        product_id = links[[ "ad", ad_id ]] || links[[ "ad_set", adset_id ]] || links[[ "campaign", campaign_id ]]
        product_id ? by_product[product_id] += spend : unassigned += spend
      end
      Result.new(by_product: by_product.to_h, unassigned: unassigned, unconverted_rows: rows.where(spend_display: nil).count,
        currency: Fx.normalize(store.currency))
    end
  end
end
