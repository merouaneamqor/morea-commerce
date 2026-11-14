module Confirmations
  # Who was clocked in and when, for the owner: one summary per agent (time worked, number of shifts, first arrival, last departure, on
  # shift now) and the log of every shift of the range, newest first. Every query is scoped to the store.
  class Attendance
    Summary = Data.define(:user, :worked_seconds, :shifts_count, :first_in, :last_out, :open_since, :last_seen_at)

    def initialize(store:, range:, agent_id: nil, now: Time.current)
      @store, @range, @agent_id, @now = store, range, agent_id.presence&.to_i, now
    end

    def shifts
      @shifts ||= begin
        scope = ConfirmationShift.where(store: @store).overlapping(@range).includes(:user).order(started_at: :desc)
        scope = scope.where(user_id: @agent_id) if @agent_id
        scope.limit(500).to_a
      end
    end

    # The people who work the desk, the busiest first; someone who never clocked in stays in the list with no hours.
    def summaries
      @summaries ||= begin
        by_user = shifts.group_by(&:user_id)
        people.map do |user|
          mine = by_user.fetch(user.id, [])
          Summary.new(user: user, worked_seconds: mine.sum { |shift| shift.seconds_within(@range, now: @now) }.round, shifts_count: mine.size,
                      first_in: mine.map(&:started_at).min, last_out: mine.filter_map(&:ended_at).max,
                      open_since: mine.find { |shift| shift.ended_at.nil? }&.started_at, last_seen_at: mine.find { |shift| shift.ended_at.nil? }&.last_seen_at)
        end.sort_by { |summary| [ -summary.worked_seconds, summary.user.id ] }
      end
    end

    def agents = people

    def total_seconds = summaries.sum(&:worked_seconds)

    private

    def people
      @people ||= @store.users.active.where(confirmation_role: User::CONFIRMATION_ROLES).or(@store.users.active.where(admin: true)).order(:name, :id).to_a
    end
  end
end
