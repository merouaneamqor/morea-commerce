# frozen_string_literal: true

module Types
  module Funnel
    class StageType < BaseObject
      field :key, String, null: false
      field :visits, Integer, null: false
      field :share_of_landed, Float, null: false
      field :drop_from_previous, Float, null: true
    end

    class SourceType < BaseObject
      field :label, String, null: false
      field :visits, Integer, null: false
      field :checkouts, Integer, null: false
      field :orders, Integer, null: false
      field :conversion_rate, Float, null: false
    end

    class LandingType < BaseObject
      field :path, String, null: false
      field :visits, Integer, null: false
      field :orders, Integer, null: false
    end

    class SummaryType < BaseObject
      field :from, GraphQL::Types::ISO8601Date, null: false
      field :to, GraphQL::Types::ISO8601Date, null: false
      field :total_visits, Integer, null: false
      field :abandoned_visits, Integer, null: false
      field :attributed_orders, Integer, null: false
      field :stages, [ StageType ], null: false
      field :sources, [ SourceType ], null: false
      field :landings, [ LandingType ], null: false
      field :sources_limit, Integer, null: false
      field :landings_limit, Integer, null: false
      field :cache_hit, Boolean, null: false
    end
  end
end
