module Confirmations
  # Per-agent and store-wide desk figures for one reporting range. Every query is
  # scoped to the store, so a request cannot read another workspace's staff or attempts.
  class Performance
    COUNTED = %i[worked_seconds attempts confirmed cancelled no_answer callbacks open_claims].freeze

    Figures = Data.define(*COUNTED) do
      def +(other)
        self.class.new(**COUNTED.index_with { |key| public_send(key) + other.public_send(key) })
      end

      def confirmation_rate = attempts.zero? ? nil : confirmed.fdiv(attempts)
      def confirmations_per_hour = worked_seconds.zero? ? nil : confirmed / (worked_seconds / 3600.0)
    end

    Row = Data.define(:user, :on_shift, :figures)

    # `only:` limits rows and totals to one agent's own figures.
    def initialize(store:, range:, now: Time.current, only: nil)
      @store, @range, @now, @only = store, range, now, only
    end

    def rows
      @rows ||= agents.map do |user|
        Row.new(user: user, on_shift: open_user_ids.include?(user.id), figures: figures_for(user.id))
      end
    end

    # Includes departed staff, so totals keep the history their attempts recorded.
    def totals
      @totals ||= user_ids.map { |id| figures_for(id) }.reduce(Figures.new(**COUNTED.index_with(0))) { |sum, figures| sum + figures }
    end

    def agents_on_shift = rows.count(&:on_shift)

    private

    def agents
      @agents ||= begin
        scope = @store.users.active.where(admin: true).or(@store.users.active.where(confirmation_role: "agent"))
        scope = scope.where(id: @only.id) if @only
        scope.order(:email).to_a
      end
    end

    def user_ids
      return [ @only.id ] if @only

      (worked_seconds.keys | outcomes.keys | claims.keys)
    end

    def figures_for(user_id)
      counts = outcomes.fetch(user_id, {})
      Figures.new(
        worked_seconds: worked_seconds.fetch(user_id, 0).round,
        attempts: counts.values.sum,
        confirmed: counts.fetch("confirmed", 0),
        cancelled: counts.fetch("cancelled", 0),
        no_answer: counts.fetch("no_answer", 0),
        callbacks: counts.fetch("callback", 0),
        open_claims: claims.fetch(user_id, 0)
      )
    end

    def worked_seconds
      @worked_seconds ||= ConfirmationShift.where(store: @store).overlapping(@range).each_with_object(Hash.new(0)) do |shift, totals|
        totals[shift.user_id] += shift.seconds_within(@range, now: @now)
      end
    end

    def outcomes
      @outcomes ||= ConfirmationAttempt.where(store: @store, created_at: @range).group(:user_id, :outcome).count
        .each_with_object({}) { |((user_id, outcome), count), nested| (nested[user_id] ||= {})[outcome] = count }
    end

    def claims
      @claims ||= OrderConfirmation.where(store: @store).where.not(assigned_user_id: nil).group(:assigned_user_id).count
    end

    def open_user_ids
      @open_user_ids ||= ConfirmationShift.open.where(store: @store).pluck(:user_id)
    end
  end
end
