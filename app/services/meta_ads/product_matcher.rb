# frozen_string_literal: true

module MetaAds
  # Links campaigns, ad sets and ads to products when their name holds exactly one product's SKU or name.
  # An ambiguous name (two products match) or an unrelated one stays unlinked for the merchant to map by hand.
  # Existing links, manual or automatic, are left as they are.
  class ProductMatcher
    MIN_SKU = 3
    MIN_NAME = 4

    KINDS = { "ad" => MetaAds::Ad, "ad_set" => MetaAds::AdSet, "campaign" => MetaAds::Campaign }.freeze

    def self.call(store:)
      new(store).call
    end

    def initialize(store)
      @store = store
    end

    def call
      matchers = @store.products.pluck(:id, :name, :sku).filter_map { |id, name, sku| [ id, patterns(name, sku) ] if patterns(name, sku).any? }
      return 0 if matchers.empty?

      created = 0
      KINDS.each do |type, model|
        linked = ProductLink.where(store_id: @store.id, object_type: type).pluck(:meta_id).to_set
        model.where(store_id: @store.id).where.not(name: [ nil, "" ]).pluck(:meta_id, :name).each do |meta_id, name|
          next if linked.include?(meta_id)

          text = normalize(name)
          hits = matchers.select { |_, regexps| regexps.any? { |regexp| regexp.match?(text) } }.map(&:first)
          next unless hits.size == 1

          ProductLink.create!(store_id: @store.id, product_id: hits.first, object_type: type, meta_id: meta_id, source: "auto")
          created += 1
        rescue ActiveRecord::RecordNotUnique
          next
        end
      end
      created
    end

    private

    def patterns(name, sku)
      list = []
      list << whole(sku) if sku.to_s.strip.length >= MIN_SKU
      list << whole(name) if name.to_s.strip.length >= MIN_NAME
      list
    end

    def whole(text)
      /(?<![[:alnum:]])#{Regexp.escape(normalize(text))}(?![[:alnum:]])/
    end

    def normalize(text)
      I18n.transliterate(text.to_s).downcase.squish
    end
  end
end
