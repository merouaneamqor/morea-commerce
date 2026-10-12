# frozen_string_literal: true

class MoreaSchema < GraphQL::Schema
  max_depth 12

  query Types::QueryType
  mutation Types::MutationType
end
