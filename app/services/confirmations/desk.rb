module Confirmations
  # Lock the order before creating/locking its confirmation row: one claimant wins,
  # and the disposition, audit attempt and stock transition commit together.
  #
  # Call panel: open_call claims the order (the claim is the lock, nobody else can open or act on it)
  # and starts the server-side call clock; finish_call saves the edits, the result and the measured
  # duration together; abandon_call closes the panel without a result.
  class Desk
    class Error < StandardError; end

    NO_ANSWER_LIMIT = 3
    AUTO_CANCEL_REASON = "Auto-cancelled after #{NO_ANSWER_LIMIT} unanswered calls".freeze
    # Closing the panel after more than this many seconds still counts as one call attempt.
    ABANDON_COUNT_AFTER = 5

    def initialize(store:, user:)
      @store, @user = store, user
    end

    def claim(order_id)
      with_order(order_id) do |order, confirmation|
        require_shift!
        require_open!(order)
        take!(order, confirmation)
      end
    end

    def release(order_id)
      with_order(order_id) do |order, confirmation|
        require_owner!(confirmation)
        confirmation.update!(assigned_user: nil, claimed_at: nil, call_started_at: nil, last_activity_at: nil)
        order.record_event!("comment", body: "Confirmation claim released", user: @user)
        confirmation
      end
    end

    # Owner or manager releases a claim by hand ("Libérer"), whoever holds it.
    def force_release(order_id)
      raise Error, "Only owners and managers can release an order." if @user.confirmation_agent_view?

      with_order(order_id) do |order, confirmation|
        holder = confirmation.assigned_user
        confirmation.update!(assigned_user: nil, claimed_at: nil, call_started_at: nil, last_activity_at: nil)
        order.record_event!("comment", body: "Claim released by #{@user.name.presence || @user.email}#{" (held by #{holder.name.presence || holder.email})" if holder}", user: @user)
        confirmation
      end
    end

    # Keeps the open call alive: the panel pings while it is open so a long call is not released.
    def touch_call(order_id)
      with_order(order_id) do |_order, confirmation|
        require_owner!(confirmation)
        confirmation.update!(last_activity_at: Time.current)
        confirmation
      end
    end

    # The agent opened WhatsApp for this order: we log who and when. It does not prove delivery.
    def log_whatsapp(order_id)
      with_order(order_id) do |order, _confirmation|
        require_shift!
        order.record_event!("whatsapp", body: "WhatsApp opened by #{@user.name.presence || @user.email}", user: @user)
        order
      end
    end

    # Block the order's number for the store (reason required). This order leaves the queue for "Bloqués".
    def block_number(order_id, reason:)
      reason = reason.to_s.strip
      raise Error, "Give a reason to block this number." if reason.blank?

      with_order(order_id) do |order, confirmation|
        require_shift!
        BlockedPhone.block!(store: @store, phone: order.customer_phone, reason: reason, user: @user)
        BlockedPhone.block!(store: @store, phone: order.second_phone, reason: reason, user: @user) if order.second_phone.present?
        confirmation.update!(disposition: "blocked", assigned_user: nil, claimed_at: nil, call_started_at: nil, last_activity_at: nil, callback_at: nil)
        order.record_event!("comment", body: "Number blocked — #{reason}", user: @user)
        confirmation
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    # Owner or manager unblocks the number: it leaves the list and its blocked orders go back to the queue.
    def unblock(order_id)
      raise Error, "Only owners and managers can unblock a number." if @user.confirmation_agent_view?

      with_order(order_id) do |order, _confirmation|
        keys = [ order.customer_phone, order.second_phone ].map { |phone| BlockedPhone.key_for(phone) }.reject(&:blank?)
        BlockedPhone.where(store: @store, phone_key: keys).delete_all
        OrderConfirmation.where(store: @store, disposition: "blocked").includes(:order).find_each do |row|
          next unless ([ row.order.customer_phone, row.order.second_phone ].map { |phone| BlockedPhone.key_for(phone) } & keys).any?

          row.update!(disposition: "pending")
          row.order.record_event!("comment", body: "Number unblocked by #{@user.name.presence || @user.email}: back in the queue", user: @user)
        end
        order
      end
    end

    # Manager fixes a wrong number and sends the order back to the queue.
    def requeue(order_id, phone:)
      raise Error, "Only owners and managers can send an order back to the queue." if @user.confirmation_agent_view?

      with_order(order_id) do |order, confirmation|
        raise Error, "Only orders flagged as wrong number can be sent back." unless confirmation.disposition == "wrong_number"
        require_open!(order)

        attrs = { name: order.customer_name, phone: phone.to_s, city: order.customer_city, district: order.customer_district, address: order.customer_address,
                  second_phone: order.second_phone, notes: order.notes, tags: order.tags,
                  lines: order.order_items.map { |item| { product_id: item.product_id, product_variant_id: item.product_variant_id, quantity: item.quantity } } }
        apply_changes!(order, attrs)
        blocked = BlockedPhone.blocked?(@store, order.reload.customer_phone, order.second_phone)
        confirmation.update!(disposition: blocked ? "blocked" : "pending", callback_at: nil)
        order.record_event!("comment", body: "Sent back to the queue by #{@user.name.presence || @user.email} with a corrected number", user: @user)
        confirmation
      end
    end

    # "Appeler": claim + start the call clock. Reopening your own open call keeps the original start.
    def open_call(order_id)
      with_order(order_id) do |order, confirmation|
        require_shift!
        require_open!(order)
        take!(order, confirmation)
        confirmation.update!(call_started_at: confirmation.call_started_at || Time.current, last_activity_at: Time.current)
        confirmation
      end
    end

    # "Annuler" in the panel: nothing is saved, but a call that ran more than 5 seconds is one attempt.
    def abandon_call(order_id)
      with_order(order_id) do |_order, confirmation|
        require_owner!(confirmation)
        seconds = call_seconds(confirmation)
        if seconds && seconds > ABANDON_COUNT_AFTER
          confirmation.confirmation_attempts.create!(store: @store, user: @user, outcome: "abandoned", call_seconds: seconds, handled_seconds: handled_seconds(confirmation))
        end
        confirmation.update!(call_started_at: nil, last_activity_at: Time.current)
        confirmation
      end
    end

    # "Terminer l'appel": edits (editor attributes, optional), result and duration in one transaction.
    def finish_call(order_id, outcome:, notes: nil, callback_at: nil, changes: nil)
      outcome = outcome.to_s
      raise Error, "Pick the result of the call." unless ConfirmationAttempt::RESULTS.include?(outcome)
      raise Error, "Give a reason to cancel the order." if outcome == "cancelled" && notes.to_s.strip.blank?

      record(order_id, outcome: outcome, notes: notes, callback_at: callback_at, panel: true, changes: changes)
    end

    def record(order_id, outcome:, notes: nil, callback_at: nil, panel: false, changes: nil)
      outcome = outcome.to_s
      raise Error, "Choose a valid outcome." unless ConfirmationAttempt::RESULTS.include?(outcome)
      notes = notes.to_s.strip.presence
      raise Error, "Notes must be 2000 characters or fewer." if notes && notes.length > 2000
      callback = parse_callback(callback_at, outcome)

      with_order(order_id) do |order, confirmation|
        require_shift!
        require_open!(order)
        require_owner!(confirmation)
        raise Error, "Open the call before finishing it." if panel && confirmation.call_started_at.nil?

        measured = panel ? call_seconds(confirmation) : nil
        apply_changes!(order, changes) if changes
        # The order lock serializes this count, so the third unanswered call always cancels.
        auto_cancel = outcome == "no_answer" && no_answer_count(confirmation) + 1 >= NO_ANSWER_LIMIT
        # Time held since the claim started; read before the claim is cleared below.
        handled = handled_seconds(confirmation)
        if auto_cancel
          order.transition_to!("cancelled", reason: AUTO_CANCEL_REASON, user: @user, source: :staff, sync_delivery: false)
        elsif %w[confirmed cancelled].include?(outcome)
          order.transition_to!(outcome, reason: notes, user: @user, source: :staff, sync_delivery: false)
        end
        confirmation.update!(disposition: auto_cancel ? "cancelled" : outcome, callback_at: callback, assigned_user: nil, claimed_at: nil, call_started_at: nil, last_activity_at: nil)
        confirmation.confirmation_attempts.create!(store: @store, user: @user, outcome: outcome, notes: notes, callback_at: callback, handled_seconds: handled, call_seconds: measured)
        body = "Confirmation outcome: #{outcome.humanize}#{" — #{notes}" if notes}"
        body = "#{body}. #{AUTO_CANCEL_REASON}" if auto_cancel
        body = "#{body} (call #{measured}s)" if measured
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
      # Idle claims are released first (and committed on their own): an agent who comes back after
      # 15 minutes of silence finds the order released instead of acting on a stale claim.
      ClaimExpiry.release_idle!(@store)
      Order.transaction do
        order = @store.orders.lock.find(order_id)
        confirmation = OrderConfirmation.find_or_create_by!(order: order) { |row| row.store = @store }
        raise Error, "Confirmation belongs to another store." unless confirmation.store_id == @store.id
        yield order, confirmation
      end
    end

    # Claim for this user unless it is already theirs; refuses an order another agent holds.
    def take!(order, confirmation)
      raise Error, "This callback is not due yet." unless confirmation.due?
      if confirmation.assigned_user_id && confirmation.assigned_user_id != @user.id
        raise Error, "Another agent has claimed this order."
      end
      unless confirmation.assigned_user_id == @user.id
        confirmation.update!(assigned_user: @user, claimed_at: Time.current, last_activity_at: Time.current)
        order.record_event!("comment", body: "Order claimed for confirmation", user: @user)
      end
      confirmation
    end

    # The edits of the call panel, applied through the order editor (stock, totals, customer) and written
    # to the history with who, what and when: one line per changed field.
    def apply_changes!(order, attrs)
      before = snapshot(order)
      # The editor rebuilds the totals from what it is given: keep shipping and discount as they are.
      keep = { shipping_dh: order.shipping_cents.to_i / 100.0, discount_code: order.discount_code.presence,
               discount_dh: (order.discount_code.blank? ? order.discount_cents.to_i / 100.0 : nil) }
      attrs = keep.merge(attrs.to_h.symbolize_keys)
      editor = Orders::Editor.new(store: @store, user: @user, external_effects: false)
      raise Error, order.edit_lock_reason.presence || "This order can no longer be edited." unless order.editable?
      raise Error, editor.errors.full_messages.to_sentence.presence || "Could not save the changes." unless editor.update(order, attrs)

      differences = describe_changes(before, snapshot(order.reload))
      order.record_event!("edited", body: "Call edit: #{differences.join("; ")}", user: @user) if differences.any?
    end

    def snapshot(order)
      {
        "name" => order.customer_name, "phone" => order.customer_phone, "second phone" => order.second_phone.to_s,
        "city" => order.customer_city, "address" => order.customer_address,
        "lines" => order.order_items.reload.map { |item| [ item.product_name, item.variant_name, item.quantity ] },
        "total" => order.total_cents
      }
    end

    def describe_changes(before, after)
      list = (before.keys - %w[lines total]).filter_map { |key| "#{key}: #{before[key].presence || "empty"} → #{after[key].presence || "empty"}" if before[key] != after[key] }
      if before["lines"] != after["lines"]
        render_lines = ->(lines) { lines.map { |name, variant, qty| "#{qty} × #{[ name, variant ].compact_blank.join(" ")}" }.join(", ") }
        list << "products: #{render_lines.call(before["lines"])} → #{render_lines.call(after["lines"])}"
      end
      list << "total: #{before["total"] / 100.0} → #{after["total"] / 100.0} #{@store.currency}" if before["total"] != after["total"]
      list
    end

    def call_seconds(confirmation)
      return unless confirmation.call_started_at

      [ (Time.current - confirmation.call_started_at).round, 0 ].max
    end

    def handled_seconds(confirmation)
      confirmation.claimed_at && [ (Time.current - confirmation.claimed_at).round, 0 ].max
    end

    def authorize!
      return if @store && @user&.can_work_desk_for?(@store.id)

      raise Error, "Store administration access required."
    end

    # Agents must be clocked in to claim or handle orders (looking needs no shift). Checked
    # here so a crafted request cannot skip the disabled buttons.
    def require_shift!
      return unless @user.confirmation_agent_view?
      return if ConfirmationShift.open.exists?(store: @store, user: @user)

      raise Error, I18n.t("admin.confirmations.clock_in_required")
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
