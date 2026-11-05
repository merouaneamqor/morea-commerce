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
        confirmation.update!(assigned_user: nil, claimed_at: nil, call_started_at: nil)
        order.record_event!("comment", body: "Confirmation claim released", user: @user)
        confirmation
      end
    end

    # "Appeler": claim + start the call clock. Reopening your own open call keeps the original start.
    def open_call(order_id)
      with_order(order_id) do |order, confirmation|
        require_shift!
        require_open!(order)
        take!(order, confirmation)
        confirmation.update!(call_started_at: confirmation.call_started_at || Time.current)
        confirmation
      end
    end

    # "Annuler" in the panel: nothing is saved, but a call that ran more than 5 seconds is one attempt.
    def abandon_call(order_id)
      with_order(order_id) do |order, confirmation|
        require_contact!(order)
        require_owner!(confirmation)
        seconds = call_seconds(confirmation)
        if seconds && seconds > ABANDON_COUNT_AFTER
          confirmation.confirmation_attempts.create!(store: @store, user: @user, outcome: "abandoned", call_seconds: seconds, handled_seconds: handled_seconds(confirmation))
        end
        confirmation.update!(call_started_at: nil)
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
        confirmation.update!(disposition: auto_cancel ? "cancelled" : outcome, callback_at: callback, assigned_user: nil, claimed_at: nil, call_started_at: nil)
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
        confirmation.update!(assigned_user: @user, claimed_at: Time.current)
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
      existing = {
        name: order.customer_name, phone: order.customer_phone, second_phone: order.second_phone,
        city: order.customer_city, district: order.customer_district, address: order.customer_address,
        lines: order.order_items.map { |item| { product_id: item.product_id, product_variant_id: item.product_variant_id, quantity: item.quantity } }
      }
      attrs = existing.merge(keep).merge(attrs.to_h.symbolize_keys)
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
      require_contact!(order)
      unless order.status == "new" && !order.archived? && order.sendit_code.blank?
        raise Error, "Only active, unshipped new orders can be confirmed here."
      end
    end

    def require_contact!(order)
      raise Error, I18n.t("import_contact.blocked") if order.contact_review_required?
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
