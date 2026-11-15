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
      Attribution::Params.from_hash(@session[:storefront_attribution] || {})
    end

    private

    def find_or_create_visit!(path:)
      token = @cookies[COOKIE].to_s.presence || new_token
      visit = @store.storefront_visits.find_by(token: token)
      if visit
        write_cookie(token)
        return visit
      end

      now = Time.current
      path_text = path.to_s.first(Attribution::Params::PATH_LIMIT).presence
      visit = @store.storefront_visits.create!(
        **attribution_for_visit.slice(*visit_attr_keys),
        token: token,
        landing_path: path_text,
        last_path: path_text,
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
      Attribution::Params.merge_first_touch(session_attribution, {})
    end

    def assign_attribution(visit, attrs)
      visit_attr_keys.each do |key|
        next if visit.public_send(key).present?

        value = attrs[key]
        visit.public_send("#{key}=", value) if value.present?
      end
    end

    def visit_attr_keys
      %i[utm_source utm_medium utm_campaign utm_term utm_content fbclid gclid ttclid
         meta_campaign_id meta_adset_id meta_ad_id referrer landing_path]
    end

    def new_token
      SecureRandom.hex(TOKEN_BYTES)
    end

    def write_cookie(token)
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
