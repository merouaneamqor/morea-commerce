module Confirmations
  # One agent's home: points, orders in hand, and time spent on recent outcomes.
  # Every query is scoped to the store and to this agent only.
  class AgentHome
    # Points per recorded outcome. A no-answer still earns a little for the effort.
    POINTS = { "confirmed" => 10, "callback" => 3, "cancelled" => 2, "no_answer" => 1 }.freeze
    RECENT_LIMIT = 10

    def initialize(store:, user:, range:)
      @store, @user, @range = store, user, range
    end

    def points
      attempts.sum { |attempt| POINTS.fetch(attempt.outcome, 0) }
    end

    def outcome_counts
      attempts.each_with_object(Hash.new(0)) { |attempt, counts| counts[attempt.outcome] += 1 }
    end

    def confirmation_rate
      attempts.empty? ? nil : outcome_counts["confirmed"].fdiv(attempts.size)
    end

    def average_handled_seconds
      times = attempts.filter_map(&:handled_seconds)
      times.empty? ? nil : times.sum / times.size
    end

    # Orders this agent holds right now, longest-held first.
    def active_claims
      OrderConfirmation.where(store: @store, assigned_user: @user).includes(:order).order(:claimed_at).to_a
    end

    def recent
      attempts.first(RECENT_LIMIT)
    end

    private

    def attempts
      @attempts ||= ConfirmationAttempt.where(store: @store, user: @user, created_at: @range)
        .includes(order_confirmation: :order).order(created_at: :desc).to_a
    end
  end
end
