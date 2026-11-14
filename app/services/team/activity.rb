module Team
  # Who is online and what each person did today, for the "Activité de l'équipe" panel: presence (an open shift, kept alive by the page heartbeat), time worked,
  # first and last activity, and what was done (calls, confirmations, deliveries). The day is the store's day. Scoped to the store.
  class Activity
    Row = Data.define(:user, :role, :online, :last_seen_at, :worked_seconds, :first_at, :last_at, :calls, :confirmed, :delivered)

    def initialize(store:, users:, day: DateRange.today, now: Time.current)
      @store, @users, @day, @now = store, users, day, now
    end

    def range = @range ||= @day.in_time_zone(DateRange::ZONE).all_day

    def rows
      @rows ||= @users.map { |user| row_for(user) }.sort_by { |row| [ row.online ? 0 : 1, -row.worked_seconds, row.user.id ] }
    end

    def online_count = rows.count(&:online)
    def total = rows.size
    def worked_total = rows.sum(&:worked_seconds)

    # Average over the people who worked at all.
    def worked_average
      workers = rows.count { |row| row.worked_seconds.positive? }
      workers.zero? ? 0 : worked_total / workers
    end

    def calls_total = rows.sum(&:calls)
    def callers = rows.count { |row| row.calls.positive? }
    def confirmed_total = rows.sum(&:confirmed)
    def delivered_total = rows.sum(&:delivered)
    def actions_total = calls_total + confirmed_total + delivered_total

    # Rows that match the filters of the panel: presence ("online" / "offline"), role ("owner" / "agent") and a search on the name or email.
    def filtered(presence: nil, role: nil, query: nil)
      rows.select do |row|
        (presence.blank? || presence == "all" || (presence == "online") == row.online) &&
          (role.blank? || role == "all" || row.role.to_s == role) &&
          (query.blank? || "#{row.user.name} #{row.user.email}".downcase.include?(query.to_s.strip.downcase))
      end
    end

    private

    def row_for(user)
      shifts = shifts_by_user.fetch(user.id, [])
      open_shift = shifts.find { |shift| shift.ended_at.nil? }
      outcomes = attempts_by_user.fetch(user.id, {})
      Row.new(
        user: user, role: Roles.for_user(user), online: open_shift.present?,
        last_seen_at: open_shift ? (open_shift.last_seen_at || open_shift.started_at) : shifts.filter_map(&:ended_at).max,
        worked_seconds: shifts.sum { |shift| shift.seconds_within(range, now: @now) }.round,
        first_at: shifts.map { |shift| [ shift.started_at, range.begin ].max }.min,
        last_at: shifts.map { |shift| shift.ended_at || shift.last_seen_at || @now }.max,
        calls: outcomes.values.sum, confirmed: outcomes.fetch("confirmed", 0),
        delivered: earnings.delivered_orders(user).where(delivered_at: range).count
      )
    end

    def shifts_by_user
      @shifts_by_user ||= ConfirmationShift.where(store: @store, user_id: @users.map(&:id)).overlapping(range).group_by(&:user_id)
    end

    # { user_id => { outcome => count } } of the calls recorded today.
    def attempts_by_user
      @attempts_by_user ||= ConfirmationAttempt.where(store: @store, user_id: @users.map(&:id), created_at: range).group(:user_id, :outcome).count
        .each_with_object({}) { |((user_id, outcome), count), by_user| (by_user[user_id] ||= {})[outcome] = count }
    end

    def earnings = @earnings ||= AgentEarnings.new(store: @store, range: range)
  end
end
