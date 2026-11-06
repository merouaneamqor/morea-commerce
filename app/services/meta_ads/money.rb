# frozen_string_literal: true

module MetaAds
  # Meta budget fields arrive as integer minor units. Insights `spend` is already a major-unit decimal.
  # Offset 1 currencies match Meta's zero-decimal list; everything else divides by 100.
  module Money
    ZERO_DECIMAL = %w[BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX VND VUV XAF XOF XPF].freeze

    module_function

    def offset(currency)
      ZERO_DECIMAL.include?(currency.to_s.upcase) ? 1 : 100
    end

    # Converts a Meta budget string/integer into a major-unit BigDecimal, or nil when blank/invalid.
    def from_minor(value, currency:)
      return if value.nil? || value.to_s.strip.empty?

      minor = BigDecimal(value.to_s, exception: false)
      return unless minor&.finite? && !minor.negative?

      (minor / offset(currency)).round(4)
    end
  end
end
