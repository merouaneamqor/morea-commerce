# frozen_string_literal: true

module Storefront
  # Creates or updates the anonymous visit row and appends a funnel event.
  class VisitTracker
    COOKIE = :morea_visit_token
    TOKEN_BYTES = 16
    VISIT_TTL = 30.days

    def initialize(store:, cookies:, session:, measurement_allowed:)
      @store = store
      @cookies = cookies
      @session = session
      @measurement_allowed = measurement_allowed
    end

    # Always keep first-touch UTM / click ids in the Rails session for order attribution.
    def capture_attribution!(request)
      incoming = Attribution::Params.from_request(request)
      return if incoming.except(:landing_path, :referrer).empty? && @session[:storefront_attribution].present?

      merged = Attribution::Params.merge_first_touch(@session[:storefront_attribution], incoming)
      @session[:storefront_attribution] = merged.stringify_keys if merged.any?
    end

    def record!(stage:, path: nil, product_id: nil, metadata: {}, order: nil)
      return unless @store && @measurement_allowed

      visit = find_or_create_visit!(path: path)
      return unless visit

      attrs = attribution_for_visit
      assign_attribution(visit, attrs) if attrs.any?
      visit.last_path = path.to_s.first(Attribution::Params::PATH_LIMIT) if path.present?
      visit.last_seen_at = Time.current
      if order
        visit.order = order
        visit.converted_at ||= Time.current
      end
      visit.advance_stage!(stage) if StorefrontVisit::STAGES.include?(stage.to_s)
      visit.save! if visit.changed?

      already = visit.storefront_funnel_events.where(name: stage.to_s).exists?
      return visit if already && stage.to_s != "abandoned"

      visit.storefront_funnel_events.create!(
        store: @store,
        name: stage.to_s,
        path: path.to_s.first(Attribution::Params::PATH_LIMIT).presence,
        product_id: product_id,
        metadata: metadata.is_a?(Hash) ? metadata.slice("product_slug", "product_id", "order_number").compact : {},
        created_at: Time.current
      )
      visit
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      visit
    end

    def session_attribution
      Attribution::Params.merge_first_touch(@session[:storefront_attribution] || {}, {})
    end

    private

    def find_or_create_visit!(path:)
      token = read_cookie_token || new_token
      visit = @store.storefront_visits.find_by(token: token)
      if visit
        write_cookie(token)
        return visit
      end

      now = Time.current
      path_text = path.to_s.first(Attribution::Params::PATH_LIMIT).presence
      attrs = truncated_attribution(attribution_for_visit)
      visit = @store.storefront_visits.create!(
        **attrs,
        token: token,
        landing_path: path_text || attrs[:landing_path],
        last_path: path_text || attrs[:landing_path],
        landed_at: now,
        last_seen_at: now,
        funnel_stage: "landed"
      )
      visit.storefront_funnel_events.create!(
        store: @store,
        name: "landed",
        path: path_text,
        metadata: {},
        created_at: now
      )
      write_cookie(token)
      visit
    rescue ActiveRecord::RecordNotUnique
      @store.storefront_visits.find_by(token: token)
    end

    def attribution_for_visit
      Attribution::Params.merge_first_touch(@session[:storefront_attribution] || {}, {})
    end

    def truncated_attribution(attrs)
      limits = {
        utm_source: 100, utm_medium: 100, utm_campaign: 200, utm_term: 200, utm_content: 200,
        fbclid: 255, gclid: 255, ttclid: 255,
        meta_campaign_id: 25, meta_adset_id: 25, meta_ad_id: 25,
        referrer: 500, landing_path: 500
      }
      limits.each_with_object({}) do |(key, limit), result|
        value = attrs[key].to_s
        next if value.blank?

        result[key] = value.first(limit)
      end
    end

    def assign_attribution(visit, attrs)
      truncated_attribution(attrs).each do |key, value|
        next if visit.public_send(key).present?

        visit.public_send("#{key}=", value)
      end
    end

    def new_token
      SecureRandom.hex(TOKEN_BYTES)
    end

    def read_cookie_token
      raw = @cookies[COOKIE]
      value =
        case raw
        when Hash then raw[:value].presence || raw["value"].presence
        else raw
        end
      text = value.to_s
      text.presence&.first(64)
    end

    def write_cookie(token)
      # Plain hashes (unit tests) store the token string; CookieJar takes the options hash.
      if @cookies.is_a?(Hash)
        @cookies[COOKIE] = token
        return
      end

      @cookies[COOKIE] = {
        value: token,
        expires: VISIT_TTL.from_now,
        path: "/",
        httponly: true,
        same_site: :lax,
        secure: !Rails.env.local?
      }
    end
  end
end
