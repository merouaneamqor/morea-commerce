module Confirmations
  # Clock in/out for the confirmation desk. The user row lock serializes repeated
  # clicks; the partial unique index on open shifts is the final guard.
  class Shifts
    class Error < StandardError; end

    # The page says "I am here" every 30 seconds while it is open and visible. Without it for this long the agent is gone.
    PRESENCE_GRACE = 3.minutes

    def initialize(store:, user:)
      @store, @user = store, user
    end

    def clock_in
      authorize!
      ConfirmationShift.transaction do
        @user.lock!
        raise Error, "You are already on shift." if open_shift
        ConfirmationShift.create!(store: @store, user: @user, started_at: Time.current, last_seen_at: Time.current)
      end
    rescue ActiveRecord::RecordNotUnique
      raise Error, "You are already on shift."
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    def clock_out
      authorize!
      shift = open_shift || raise(Error, "You are not on shift.")
      shift.with_lock do
        raise Error, "You are not on shift." if shift.ended_at
        shift.update!(ended_at: Time.current, end_reason: "manual")
      end
      ClaimExpiry.release_for!(store: @store, user: @user)
      shift
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    # A sign of life from the page. Returns false when there is no open shift any more (it was closed because the page was away too long).
    def heartbeat
      shift = open_shift
      return false unless shift

      # Back after too long away: that shift ended when they left. It is closed at the last time they were seen, not revived by this beat.
      if (shift.last_seen_at || shift.started_at) < Time.current - PRESENCE_GRACE
        self.class.close_stale!
        return false
      end

      shift.update_columns(last_seen_at: Time.current)
      true
    end

    # Closes every open shift that has had no sign of life for PRESENCE_GRACE, at the last time it was seen (never before it started).
    def self.close_stale!(now: Time.current)
      stale = ConfirmationShift.open.where("COALESCE(confirmation_shifts.last_seen_at, confirmation_shifts.started_at) < ?", now - PRESENCE_GRACE)
      stale.includes(:store, :user).find_each do |shift|
        shift.with_lock do
          next if shift.ended_at

          seen = shift.last_seen_at || shift.started_at
          shift.update!(ended_at: [ seen, shift.started_at + 1.second ].max, end_reason: "inactive")
        end
        ClaimExpiry.release_for!(store: shift.store, user: shift.user) if shift.user
      end
    end

    private

    def open_shift
      ConfirmationShift.open.find_by(store: @store, user: @user)
    end

    def authorize!
      return if @store && @user&.can_work_desk_for?(@store.id)

      raise Error, "Store administration access required."
    end
  end
end
