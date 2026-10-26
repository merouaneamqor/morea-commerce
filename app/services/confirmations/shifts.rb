module Confirmations
  # Clock in/out for the confirmation desk. The user row lock serializes repeated
  # clicks; the partial unique index on open shifts is the final guard.
  class Shifts
    class Error < StandardError; end

    def initialize(store:, user:)
      @store, @user = store, user
    end

    def clock_in
      authorize!
      ConfirmationShift.transaction do
        @user.lock!
        raise Error, "You are already on shift." if open_shift
        ConfirmationShift.create!(store: @store, user: @user, started_at: Time.current)
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
        shift.update!(ended_at: Time.current)
      end
      shift
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
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
