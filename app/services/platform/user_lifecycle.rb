# frozen_string_literal: true

module Platform
  # Suspends, archives and restores admin accounts. Status is the only thing
  # that changes: records, order history and audit references stay intact.
  class UserLifecycle
    ACTIONS = {
      "suspend" => { from: %w[active], to: "suspended" },
      "reactivate" => { from: %w[suspended], to: "active" },
      "archive" => { from: %w[active suspended], to: "archived" },
      "restore" => { from: %w[archived], to: "active" }
    }.freeze

    class Denied < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    def initialize(user:, actor:)
      @user = user
      @actor = actor
    end

    def call(action)
      rule = ACTIONS.fetch(action.to_s) { raise Denied, :unknown_action }

      User.transaction do
        # Serialize concurrent changes so two admins can't remove each other.
        User.super_admins.active.order(:id).lock.pluck(:id)
        @user.lock!
        raise Denied, :invalid_transition unless rule[:from].include?(@user.status)
        raise Denied, :self if @user.id == @actor.id && rule[:to] != "active"
        raise Denied, :last_super_admin if leaving_last_super_admin?(rule[:to])

        @user.update!(status: rule[:to], status_changed_at: Time.current)
      end
      @user
    end

    private

    def leaving_last_super_admin?(target)
      return false unless @user.super_admin? && @user.active? && target != "active"

      User.super_admins.active.where.not(id: @user.id).none?
    end
  end
end
