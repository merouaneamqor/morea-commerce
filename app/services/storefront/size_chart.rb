# frozen_string_literal: true

module Storefront
  # Garment measurements for the size advisor. Merchants can paste their own
  # chart on a product; otherwise we filter the unisex/menswear/womenswear
  # defaults down to the sizes that product actually sells.
  class SizeChart
    PROFILES = %w[unisex menswear womenswear].freeze
    CUTS = %w[slim regular relaxed oversized].freeze
    GARMENTS = %w[tops bottoms].freeze
    MEASURES = %w[chest waist hips length].freeze

    # Finished garment centimetres (not body). Unisex sits between menswear and
    # womenswear for modest sportswear defaults.
    DEFAULTS = {
      "unisex" => [
        { "size" => "XS", "chest" => 91, "waist" => 81, "hips" => 93, "length" => 63 },
        { "size" => "S", "chest" => 97, "waist" => 87, "hips" => 99, "length" => 65 },
        { "size" => "M", "chest" => 103, "waist" => 93, "hips" => 105, "length" => 67 },
        { "size" => "L", "chest" => 109, "waist" => 99, "hips" => 111, "length" => 69 },
        { "size" => "XL", "chest" => 115, "waist" => 105, "hips" => 117, "length" => 71 },
        { "size" => "XXL", "chest" => 121, "waist" => 111, "hips" => 123, "length" => 73 }
      ],
      "menswear" => [
        { "size" => "XS", "chest" => 96, "waist" => 90, "hips" => 94, "length" => 66 },
        { "size" => "S", "chest" => 102, "waist" => 96, "hips" => 100, "length" => 68 },
        { "size" => "M", "chest" => 108, "waist" => 102, "hips" => 106, "length" => 70 },
        { "size" => "L", "chest" => 114, "waist" => 108, "hips" => 112, "length" => 72 },
        { "size" => "XL", "chest" => 120, "waist" => 114, "hips" => 118, "length" => 74 },
        { "size" => "XXL", "chest" => 126, "waist" => 120, "hips" => 124, "length" => 76 }
      ],
      "womenswear" => [
        { "size" => "XS", "chest" => 86, "waist" => 72, "hips" => 92, "length" => 60 },
        { "size" => "S", "chest" => 91, "waist" => 77, "hips" => 97, "length" => 62 },
        { "size" => "M", "chest" => 96, "waist" => 82, "hips" => 102, "length" => 64 },
        { "size" => "L", "chest" => 102, "waist" => 88, "hips" => 108, "length" => 66 },
        { "size" => "XL", "chest" => 108, "waist" => 94, "hips" => 114, "length" => 68 },
        { "size" => "XXL", "chest" => 114, "waist" => 100, "hips" => 120, "length" => 70 }
      ]
    }.freeze

    def self.for(product, sizes: nil)
      new(product).payload(sizes: sizes)
    end

    def self.normalize(raw)
      data = raw.is_a?(Hash) ? raw.deep_stringify_keys : {}
      profile = PROFILES.include?(data["profile"].to_s) ? data["profile"].to_s : "unisex"
      cut = CUTS.include?(data["cut"].to_s) ? data["cut"].to_s : "regular"
      garment = GARMENTS.include?(data["garment"].to_s) ? data["garment"].to_s : "tops"
      rows = Array(data["rows"]).filter_map { |row| normalize_row(row) }
      { "profile" => profile, "cut" => cut, "garment" => garment, "rows" => rows }
    end

    def self.normalize_row(row)
      return if row.blank?

      hash = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row
      hash = hash.to_h if hash.respond_to?(:to_h)
      hash = hash.stringify_keys
      size = hash["size"].to_s.strip
      return if size.blank?

      measures = MEASURES.each_with_object({}) do |key, memo|
        value = hash[key].presence
        next if value.blank?

        number = value.to_f
        memo[key] = number if number.positive?
      end
      { "size" => size }.merge(measures)
    end

    def initialize(product)
      @product = product
    end

    def payload(sizes: nil)
      available = Array(sizes).presence || @product.variant_sizes
      available = available.map { |size| size.to_s.strip }.compact_blank
      stored = self.class.normalize(@product.size_chart)
      rows = stored["rows"]
      rows = default_rows(stored["profile"], available) if rows.blank? || rows_without_measures?(rows)
      rows = filter_rows(rows, available) if available.any?

      {
        "profile" => stored["profile"],
        "cut" => stored["cut"],
        "garment" => stored["garment"],
        "rows" => rows,
        "sizes" => available.presence || rows.map { |row| row["size"] }
      }
    end

    private

    def default_rows(profile, sizes)
      catalog = DEFAULTS[profile] || DEFAULTS["unisex"]
      return catalog if sizes.blank?

      matched = catalog.select { |row| sizes.map(&:upcase).include?(row["size"].upcase) }
      matched.presence || synthesize_rows(catalog, sizes)
    end

    def synthesize_rows(catalog, sizes)
      base = catalog.find { |row| row["size"] == "M" } || catalog[catalog.length / 2] || catalog.first
      sizes.map.with_index do |size, index|
        offset = (index - (sizes.length / 2)) * 6
        {
          "size" => size,
          "chest" => base["chest"] + offset,
          "waist" => base["waist"] + offset,
          "hips" => base["hips"] + offset,
          "length" => base["length"] + (offset / 3)
        }
      end
    end

    def filter_rows(rows, sizes)
      wanted = sizes.map(&:upcase)
      filtered = rows.select { |row| wanted.include?(row["size"].to_s.upcase) }
      return filtered if filtered.any?

      rows
    end

    def rows_without_measures?(rows)
      rows.none? { |row| MEASURES.any? { |measure| row[measure].present? } }
    end
  end
end
