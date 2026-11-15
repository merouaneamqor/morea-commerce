# frozen_string_literal: true

module Attribution
  # First-touch ad and UTM fields from a request or stored session hash.
  # Keeps Meta campaign ids when the merchant used the documented Facebook macros.
  module Params
    UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_term utm_content].freeze
    CLICK_KEYS = %w[fbclid gclid ttclid].freeze
    ALL_KEYS = (UTM_KEYS + CLICK_KEYS).freeze
    VALUE_LIMIT = 255
    PATH_LIMIT = 500

    module_function

    def from_request(request)
      params = request.respond_to?(:query_parameters) ? request.query_parameters : {}
      attrs = from_hash(params)
      path = request.respond_to?(:fullpath) ? request.fullpath.to_s : ""
      attrs[:landing_path] = path.first(PATH_LIMIT) if path.present?
      referrer = request.respond_to?(:referer) ? request.referer.to_s : ""
      attrs[:referrer] = referrer.first(PATH_LIMIT) if referrer.present?
      attrs.merge!(Meta.from_params(params))
      attrs
    end

    def from_hash(raw)
      return {} unless raw.is_a?(Hash)

      normalized = raw.to_h { |key, value| [ key.to_s.downcase, value ] }
      ALL_KEYS.each_with_object({}) do |key, result|
        value = scalar(normalized[key])
        result[key.to_sym] = value if value.present?
      end
    end

    # Merge incoming into existing first-touch values (first non-blank wins).
    def merge_first_touch(existing, incoming)
      existing = existing.is_a?(Hash) ? existing : {}
      incoming = incoming.is_a?(Hash) ? incoming : {}
      base = from_hash(existing)
      EXTRA_KEYS.each do |key|
        text = path_or_value(existing[key] || existing[key.to_s], key)
        base[key] = text if text.present?
      end

      next_attrs = from_hash(incoming)
      ALL_KEYS.each do |key|
        sym = key.to_sym
        base[sym] = next_attrs[sym] if base[sym].blank? && next_attrs[sym].present?
      end
      EXTRA_KEYS.each do |key|
        next if base[key].present?

        text = path_or_value(incoming[key] || incoming[key.to_s], key)
        base[key] = text if text.present?
      end

      meta = Meta.from_params(base)
      base.merge!(meta) if meta.any? && base[:meta_campaign_id].blank?
      base
    end

    def scalar(value)
      text = value.is_a?(Array) ? value.first : value
      text.to_s.strip.first(VALUE_LIMIT).presence
    end

    def path_or_value(value, key)
      text = value.is_a?(Array) ? value.first : value
      text = text.to_s.strip.presence
      return unless text

      limit = key == :landing_path || key == :referrer ? PATH_LIMIT : VALUE_LIMIT
      text.first(limit)
    end

    EXTRA_KEYS = %i[landing_path referrer meta_campaign_id meta_adset_id meta_ad_id].freeze
    private_class_method :path_or_value
  end
end
