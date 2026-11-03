# frozen_string_literal: true

module Attribution
  # Which Meta ad brought an order, read from the UTM parameters the merchant adds to every ad:
  #
  #   utm_source=facebook&utm_campaign={{campaign.id}}&utm_term={{adset.id}}&utm_content={{ad.id}}
  #
  # Rules, so that nothing is ever guessed:
  # - the source must be `facebook`;
  # - each id must be a real Meta id (digits only): an unreplaced `{{campaign.id}}` macro, a name or an empty value is ignored;
  # - an order needs at least the campaign id; the ad set and the ad are kept only when they are valid too.
  # Orders that do not match go to the "Non attribué" bucket (all three ids stay NULL).
  module Meta
    SOURCES = %w[facebook].freeze
    ID_FORMAT = /\A\d{5,25}\z/
    URL_LIMIT = 4_000
    FIELDS = { "utm_campaign" => :meta_campaign_id, "utm_term" => :meta_adset_id, "utm_content" => :meta_ad_id }.freeze

    module_function

    # Attributes to store on the order ({} when the order cannot be attributed).
    def from_payload(provider, data)
      return {} unless data.is_a?(Hash)

      candidates =
        case provider.to_s
        when "shopify" then shopify(data)
        when "woocommerce" then woocommerce(data)
        else generic(data)
        end
      candidates.each do |params|
        found = from_params(params)
        return found if found.any?
      end
      {}
    end

    # `params` is a hash of utm_* values (string or symbol keys).
    def from_params(params)
      return {} unless params.is_a?(Hash)

      params = params.to_h { |key, value| [ key.to_s.downcase, value ] }
      return {} unless SOURCES.include?(params["utm_source"].to_s.strip.downcase)

      ids = FIELDS.to_h { |param, column| [ column, id(params[param]) ] }
      ids[:meta_campaign_id] ? ids.compact : {}
    end

    # A landing page URL or a bare query string ("/products/x?utm_source=facebook&...").
    def from_url(url)
      query_params(url)
    end

    def id(value)
      text = value.to_s.strip
      text if text.match?(ID_FORMAT)
    end

    def query_params(url)
      text = url.to_s.first(URL_LIMIT)
      query = text.include?("?") ? text.split("?", 2).last : (text.include?("=") ? text : "")
      query = query.split("#", 2).first.to_s
      Rack::Utils.parse_query(query).transform_values { |value| value.is_a?(Array) ? value.first : value }
    rescue ArgumentError, Rack::QueryParser::ParameterTypeError, Rack::QueryParser::InvalidParameterError
      {}
    end

    # Shopify: note attributes (cart attributes) first, then the landing page of the order (webhook `landing_site`),
    # then UTM parameters Shopify itself recorded for the visit.
    def shopify(data)
      [ pairs(data["note_attributes"], "name", "value"), query_params(data["landing_site"]), utm_hash(data["utm"]) ]
    end

    # WooCommerce (8.5+) records UTM data as order meta `_wc_order_attribution_utm_*`, and the entry URL as
    # `_wc_order_attribution_session_entry`.
    def woocommerce(data)
      meta = pairs(data["meta_data"], "key", "value")
      stripped = meta.to_h { |key, value| [ key.to_s.delete_prefix("_wc_order_attribution_"), value ] }
      [ stripped, query_params(meta["_wc_order_attribution_session_entry"]), pairs(data["note_attributes"], "name", "value") ]
    end

    # YouCan and anything else: utm_* keys on the order, in a `utm` / `metadata` hash, or in a landing URL field.
    # (YouCan's own field names could not be verified, so this looks in every common place and never invents a value.)
    def generic(data)
      urls = %w[landing_url landing_page landing_site referrer referring_site url].filter_map { |key| data[key].presence }
      [ data, utm_hash(data["utm"]), utm_hash(data["metadata"]), utm_hash(data["extra"]), pairs(data["attributes"], "name", "value"),
        pairs(data["custom_fields"], "name", "value") ] + urls.map { |url| query_params(url) }
    end

    def utm_hash(value)
      value.is_a?(Hash) ? value : {}
    end

    # [{ "name" => "utm_source", "value" => "facebook" }, ...] -> { "utm_source" => "facebook" }
    def pairs(list, name_key, value_key)
      return {} unless list.is_a?(Array)

      list.first(200).each_with_object({}) do |row, result|
        next unless row.is_a?(Hash) && row[name_key].is_a?(String)

        result[row[name_key]] = row[value_key]
      end
    end
  end
end
