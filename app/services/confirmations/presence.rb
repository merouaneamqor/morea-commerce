module Confirmations
  # Page-open presence for a confirmation agent. An open admin page means the
  # agent can see orders; closing it, or letting the heartbeat go stale, means
  # they cannot. The intervals are stats only and are never read by pay.
  class Presence
    class Error < StandardError; end

    GRACE = ConfirmationShift::PRESENCE_GRACE

    def initialize(store:, user:)
      @store, @user = store, user
    end

    def ping!
      authorize!
      now = Time.current
      ConfirmationShift.transaction do
        @user.lock!
        close_stale!(now)
        shift = open_shift
        if shift
          shift.update!(last_seen_at: now)
        else
          ConfirmationShift.create!(store: @store, user: @user, started_at: now, last_seen_at: now)
        end
      end
    rescue ActiveRecord::RecordNotUnique
      open_shift&.update!(last_seen_at: Time.current)
    end

    def leave!
      authorize!
      shift = open_shift
      return unless shift

      now = Time.current
      ended = now > shift.started_at ? now : shift.started_at + 1.second
      shift.update!(ended_at: ended, last_seen_at: now)
    end

    def present?(now: Time.current)
      open_shift&.fresh?(now: now) || false
    end

    def seconds_within(range, now: Time.current)
      ConfirmationShift.where(store: @store, user: @user).overlapping(range).sum do |shift|
        shift.seconds_within(range, now: now)
      end
    end

    private

    def open_shift
      ConfirmationShift.open.find_by(store: @store, user: @user)
    end

    def close_stale!(now)
      shift = open_shift
      return unless shift
      return if shift.fresh?(now: now)

      seen = shift.last_seen_at || shift.started_at
      ended = seen > shift.started_at ? seen : shift.started_at + 1.second
      shift.update!(ended_at: ended)
    end

    def authorize!
      return if @store && @user&.confirmation_agent_view? && @user.can_work_desk_for?(@store.id)

      raise Error, "Confirmation agent access required."
    end
  end
end
