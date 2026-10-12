# frozen_string_literal: true

module Mutations
  class BaseMutation < GraphQL::Schema::Mutation
    def store
      context.fetch(:store)
    end

    def payload(record, key)
      if record.errors.empty?
        { key => record, errors: [] }
      else
        { key => nil, errors: record.errors.full_messages }
      end
    end

    def failure(messages)
      { errors: Array(messages) }
    end
  end
end
