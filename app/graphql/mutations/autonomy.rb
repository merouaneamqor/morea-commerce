# frozen_string_literal: true

module Mutations
  module Autonomy
    class PreviewChangeset < BaseMutation
      argument :operations, GraphQL::Types::JSON, required: true
      argument :summary, String, required: false

      field :changeset, Types::Autonomy::ChangesetType, null: true
      field :errors, [ String ], null: false

      def resolve(operations:, summary: nil)
        changeset = Catalog::Changesets.preview(store, operations: operations, summary: summary)
        { changeset: changeset, errors: [] }
      rescue Catalog::Changesets::Error => e
        failure(e.message).merge(changeset: nil)
      end
    end

    class ApplyChangeset < BaseMutation
      argument :token, String, required: true
      argument :approve_level2, Boolean, required: false
      argument :approve_level3, Boolean, required: false

      field :changeset, Types::Autonomy::ChangesetType, null: true
      field :errors, [ String ], null: false

      def resolve(token:, approve_level2: false, approve_level3: false)
        changeset = Catalog::Changesets.apply(
          store,
          token: token,
          approve_level2: approve_level2,
          approve_level3: approve_level3
        )
        { changeset: changeset, errors: [] }
      rescue Catalog::Changesets::Error => e
        failure(e.message).merge(changeset: nil)
      end
    end

    class VerifyChangeset < BaseMutation
      argument :token, String, required: true

      field :changeset, Types::Autonomy::ChangesetType, null: true
      field :errors, [ String ], null: false

      def resolve(token:)
        changeset = Catalog::Changesets.verify(store, token: token)
        { changeset: changeset, errors: [] }
      rescue Catalog::Changesets::Error => e
        failure(e.message).merge(changeset: nil)
      end
    end

    class RollbackChangeset < BaseMutation
      argument :token, String, required: true

      field :changeset, Types::Autonomy::ChangesetType, null: true
      field :errors, [ String ], null: false

      def resolve(token:)
        changeset = Catalog::Changesets.rollback(store, token: token)
        { changeset: changeset, errors: [] }
      rescue Catalog::Changesets::Error => e
        failure(e.message).merge(changeset: nil)
      end
    end

    class UpdateStoreProfile < BaseMutation
      argument :profile, GraphQL::Types::JSON, required: true

      field :profile, GraphQL::Types::JSON, null: true
      field :errors, [ String ], null: false

      def resolve(profile:)
        { profile: Catalog::Autonomy.merge_profile!(store, profile), errors: [] }
      rescue ActiveRecord::RecordInvalid => e
        failure(e.record.errors.full_messages).merge(profile: nil)
      end
    end
  end
end
