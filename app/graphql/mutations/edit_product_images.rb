# frozen_string_literal: true

module Mutations
  class EditProductImages < BaseMutation
    argument :attachment_ids, [ ID ], required: true
    argument :edit, String, required: true
    argument :confirm, Boolean, required: true

    field :result, GraphQL::Types::JSON, null: true
    field :errors, [ String ], null: false

    def resolve(attachment_ids:, edit:, confirm:)
      { result: Catalog::MediaLibrary.edit!(store, attachment_ids: attachment_ids, edit: edit, confirm: confirm), errors: [] }
    rescue Catalog::MediaLibrary::Error, ActiveRecord::RecordInvalid => e
      { result: nil, errors: [ e.message ] }
    end
  end
end
