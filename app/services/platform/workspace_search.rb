# frozen_string_literal: true

module Platform
  # Global workspace lookup for super admins by name, slug, host domain, or
  # connected shop domain. Returns at most LIMIT stores; does not mutate state.
  class WorkspaceSearch
    LIMIT = 25

    def self.call(query)
      new(query).call
    end

    def initialize(query)
      @query = query.to_s.strip
    end

    def call
      return Store.none if @query.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%"
      host_hint = @query.downcase.delete_prefix("https://").delete_prefix("http://").split("/").first.to_s
      host_pattern = "%#{ActiveRecord::Base.sanitize_sql_like(host_hint)}%"

      connection_store_ids = StoreConnection.where(
        "LOWER(external_domain) LIKE :q OR LOWER(name) LIKE :q",
        q: host_pattern
      ).select(:store_id)

      Store.where(
        "LOWER(stores.name) LIKE :q OR LOWER(stores.slug) LIKE :q OR LOWER(stores.email) LIKE :q OR stores.id IN (#{connection_store_ids.to_sql})",
        q: pattern
      ).or(
        Store.where("LOWER(stores.slug) LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(host_hint.split('.').first)}%")
      ).distinct.order(:name).limit(LIMIT)
    end
  end
end
