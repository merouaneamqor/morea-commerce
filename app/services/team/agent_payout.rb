module Team
  # Pays one agent for the orders the owner picks among the delivered orders not paid yet. Each order pays the agent's rate; the payout subtracts the
  # pending return deductions, oldest first, as many as the payment covers (a deduction is never split); the rest waits for the next payout.
  # It records how it was paid (cash or bank transfer), a reference and an optional proof. The agent row is locked, so two clicks make one payment,
  # and an order is paid at most once (AgentPaymentItem). Scoped to the store.
  class AgentPayout
    class Error < StandardError; end

    Preview = Data.define(:unpaid_cents, :deductions_cents) do
      def cash_cents = unpaid_cents - deductions_cents
    end

    def initialize(store:, agent:, paid_by:)
      @store, @agent, @paid_by = store, agent, paid_by
    end

    def rate_cents = @agent.pay_per_delivery_cents.to_i

    # The delivered orders that can still be paid, oldest first. Payments made before orders were tracked one by one (their amount is not tied to
    # orders) are assumed to have settled the oldest deliveries.
    def eligible_orders
      earnings = AgentEarnings.new(store: @store, range: Time.current.beginning_of_month..Time.current)
      linked = AgentPaymentItem.where(store: @store).select(:order_id)
      orders = earnings.delivered_orders(@agent).where.not(id: linked).to_a
      orders.drop(rate_cents.positive? ? legacy_credit_cents / rate_cents : 0)
    end

    # What paying everything that is due would settle now: the unpaid earnings and the deductions it would subtract.
    def preview(orders = eligible_orders)
      Preview.new(unpaid_cents: orders.size * rate_cents, deductions_cents: covered_deductions(orders.size * rate_cents))
    end

    # Pays the orders with these ids (all of them must be payable now).
    def pay!(order_ids:, method:, reference: nil, proof: nil)
      raise Error, "Choose how the agent was paid (cash or bank transfer)." unless AgentPayment::METHODS.include?(method.to_s)

      ids = Array(order_ids).reject(&:blank?).map(&:to_i).uniq
      raise Error, "Choose at least one order to pay." if ids.empty?

      payment = nil
      AgentPayment.transaction do
        @agent.lock!
        orders = eligible_orders.select { |order| ids.include?(order.id) }
        raise Error, "Nothing to pay." if eligible_orders.empty?
        raise Error, "Some of these orders cannot be paid (already paid, or not delivered)." if orders.size != ids.size
        raise Error, "Set a pay rate for this agent before paying." unless rate_cents.positive?

        amount = orders.size * rate_cents
        payment = AgentPayment.new(store: @store, user: @agent, paid_by: @paid_by, amount_cents: amount, paid_at: Time.current, payment_method: method.to_s, reference: reference.to_s.strip.presence)
        payment.proof.attach(proof) if proof.present?
        payment.save!
        orders.each { |order| AgentPaymentItem.create!(store: @store, agent_payment: payment, user: @agent, order: order, amount_cents: rate_cents) }
        covered = 0
        pending_deductions.lock.each do |deduction|
          break if covered + deduction.amount_cents > amount

          deduction.update!(status: "applied", agent_payment: payment)
          covered += deduction.amount_cents
        end
        payment.update!(deductions_cents: covered)
      end
      payment
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    # Pays everything that is due (the team page\x27s one-click payout).
    def pay_all!(method:, reference: nil, proof: nil)
      pay!(order_ids: eligible_orders.map(&:id), method: method, reference: reference, proof: proof)
    end

    private

    def legacy_credit_cents
      paid = AgentPayment.where(store: @store, user: @agent).sum(:amount_cents)
      [ paid - AgentPaymentItem.where(store: @store, user: @agent).sum(:amount_cents), 0 ].max
    end

    def covered_deductions(amount)
      covered = 0
      pending_deductions.each do |deduction|
        break if covered + deduction.amount_cents > amount

        covered += deduction.amount_cents
      end
      covered
    end

    def pending_deductions
      AgentDeduction.pending.where(store: @store, user: @agent).order(:created_at, :id)
    end
  end
end
