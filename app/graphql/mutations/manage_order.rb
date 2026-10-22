# frozen_string_literal: true

module Mutations
  class ManageOrder < BaseMutation
    argument :action, String, required: true
    argument :number, String, required: false
    argument :attrs, GraphQL::Types::JSON, required: false
    argument :confirm, Boolean, required: true

    field :order, GraphQL::Types::JSON, null: true
    field :errors, [ String ], null: false

    def resolve(action:, confirm:, number: nil, attrs: {})
      { order: Catalog::OrderDesk.perform(store, action: action, number: number, attrs: attrs, confirm: confirm), errors: [] }
    rescue Catalog::OrderDesk::Error => e
      { order: nil, errors: [ e.message ] }
    end
  end
end
