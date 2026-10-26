module Confirmations
  # Lock the order before creating/locking its confirmation row: one claimant wins,
  # and the disposition, audit attempt and stock transition commit together.
  class Desk
    class Error < StandardError; end

    NO_ANSWER_LIMIT = 3
    AUTO_CANCEL_REASON = "Auto-cancelled after #{NO_ANSWER_LIMIT} unanswered calls".freeze

    def initialize(store:, user:)
      @store, @user = store, user
    end

    def claim(order_id)
      with_order(order_id) do |order, confirmation|
        require_open!(order)
        raise Error, "This callback is not due yet." unless confirmation.due?
        if confirmation.assigned_user_id && confirmation.assigned_user_id != @user.id
          raise Error, "Another agent has claimed this order."
        end
        unless confirmation.assigned_user_id == @user.id
          confirmation.update!(assigned_user: @user, claimed_at: Time.current)
          order.record_event!("comment", body: "Order claimed for confirmation", user: @user)
        end
        confirmation
      end
    end

    def release(order_id)
      with_order(order_id) do |order, confirmation|
        require_owner!(confirmation)
        confirmation.update!(assigned_user: nil, claimed_at: nil)
        order.record_event!("comment", body: "Confirmation claim released", user: @user)
        confirmation
      end
    end

    def record(order_id, outcome:, notes: nil, callback_at: nil)
      outcome = outcome.to_s
      raise Error, "Choose a valid outcome." unless ConfirmationAttempt::OUTCOMES.include?(outcome)
      notes = notes.to_s.strip.presence
      raise Error, "Notes must be 2000 characters or fewer." if notes && notes.length > 2000
      callback = parse_callback(callback_at, outcome)

      with_order(order_id) do |order, confirmation|
        require_open!(order)
        require_owner!(confirmation)
        # The order lock serializes this count, so the third unanswered call always cancels.
        auto_cancel = outcome == "no_answer" && no_answer_count(confirmation) + 1 >= NO_ANSWER_LIMIT
        # Time held since the claim started; read before the claim is cleared below.
        handled = confirmation.claimed_at && [ (Time.current - confirmation.claimed_at).round, 0 ].max
        if auto_cancel
          order.transition_to!("cancelled", reason: AUTO_CANCEL_REASON, user: @user, source: :staff, sync_delivery: false)
        elsif %w[confirmed cancelled].include?(outcome)
          order.transition_to!(outcome, reason: notes, user: @user, source: :staff, sync_delivery: false)
        end
        confirmation.update!(disposition: auto_cancel ? "cancelled" : outcome, callback_at: callback, assigned_user: nil, claimed_at: nil)
        confirmation.confirmation_attempts.create!(store: @store, user: @user, outcome: outcome, notes: notes, callback_at: callback, handled_seconds: handled)
        body = "Confirmation outcome: #{outcome.humanize}#{" — #{notes}" if notes}"
        body = "#{body}. #{AUTO_CANCEL_REASON}" if auto_cancel
        order.record_event!("comment", body: body, user: @user)
        confirmation
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    rescue StandardError => e
      # Order stock validation currently raises a plain StandardError. Keep it
      # reviewable in the desk while allowing unexpected exception types to surface.
      raise unless e.instance_of?(StandardError)

      raise Error, e.message
    end

    private

    def with_order(order_id)
      authorize!
      Order.transaction do
        order = @store.orders.lock.find(order_id)
        confirmation = OrderConfirmation.find_or_create_by!(order: order) { |row| row.store = @store }
        raise Error, "Confirmation belongs to another store." unless confirmation.store_id == @store.id
        yield order, confirmation
      end
    end

    def authorize!
      return if @store && @user&.can_work_desk_for?(@store.id)

      raise Error, "Store administration access required."
    end

    def require_open!(order)
      unless order.status == "new" && !order.archived? && order.sendit_code.blank?
        raise Error, "Only active, unshipped new orders can be confirmed here."
      end
    end

    def no_answer_count(confirmation)
      confirmation.confirmation_attempts.where(outcome: "no_answer").count
    end

    def require_owner!(confirmation)
      raise Error, "Claim this order before recording or releasing it." unless confirmation.assigned_user_id == @user.id
    end

    def parse_callback(value, outcome)
      return nil unless outcome == "callback"

      time = value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) ? value : Time.zone.parse(value.to_s)
      raise Error, "Choose a callback time in the future." unless time && time > Time.current
      time
    rescue ArgumentError, TypeError
      raise Error, "Choose a valid callback time."
    end
  end
end
