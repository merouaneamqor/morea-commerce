# frozen_string_literal: true

module Morea
  # Visitor countries where ePrivacy / UK PECR style rules require prior consent
  # before loading non-essential measurement cookies. African markets (and other
  # regions outside this list) do not show the cookie banner.
  module TrackingConsentJurisdiction
    REQUIRED_COUNTRY_CODES = %w[
      AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE
      IS LI NO
      GB
      CH
    ].freeze

    COUNTRY_HEADERS = %w[
      CF-IPCountry
      CloudFront-Viewer-Country
      X-Vercel-IP-Country
      X-Country-Code
    ].freeze

    module_function

    def required?(country_code)
      REQUIRED_COUNTRY_CODES.include?(normalize(country_code))
    end

    def country_from_request(request)
      COUNTRY_HEADERS.each do |name|
        value = normalize(request.headers[name])
        return value if value.present? && value != "XX"
      end
      nil
    end

    def normalize(code)
      code.to_s.strip.upcase.presence
    end
  end
end
