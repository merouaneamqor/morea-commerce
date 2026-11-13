module Team
  # Pays one agent what they have earned and not been paid yet. The payout settles the unpaid earnings and subtracts the pending deductions, oldest first,
  # as many as the earnings cover (a deduction is never split); the rest waits for the next payout. It records how it was paid (cash or bank transfer), a
  # reference and the proof. The agent row is locked, so two clicks make one payment. Scoped to the store.
  class AgentPayout
    class Error < StandardError; end

    Preview = Data.define(:unpaid_cents, :deductions_cents) do
      def cash_cents = unpaid_cents - deductions_cents
    end

    def initialize(store:, agent:, paid_by:)
      @store, @agent, @paid_by = store, agent, paid_by
    end

    # What a payout would settle now: the unpaid earnings and the deductions it would subtract.
    def preview
      unpaid = unpaid_cents
      covered = 0
      pending_deductions.each do |deduction|
        break if covered + deduction.amount_cents > unpaid

        covered += deduction.amount_cents
      end
      Preview.new(unpaid_cents: unpaid, deductions_cents: covered)
    end

    def pay!(method:, reference: nil, proof: nil)
      raise Error, "Choose how the agent was paid (cash or bank transfer)." unless AgentPayment::METHODS.include?(method.to_s)

      payment = nil
      AgentPayment.transaction do
        @agent.lock!
        unpaid = unpaid_cents
        raise Error, "Nothing to pay." if unpaid.zero?

        payment = AgentPayment.new(store: @store, user: @agent, paid_by: @paid_by, amount_cents: unpaid, paid_at: Time.current, payment_method: method.to_s, reference: reference.to_s.strip.presence)
        payment.proof.attach(proof) if proof.present?
        payment.save!
        covered = 0
        pending_deductions.lock.each do |deduction|
          break if covered + deduction.amount_cents > unpaid

          deduction.update!(status: "applied", agent_payment: payment)
          covered += deduction.amount_cents
        end
        payment.update!(deductions_cents: covered)
      end
      payment
    rescue ActiveRecord::RecordInvalid => e
      raise Error, e.record.errors.full_messages.to_sentence
    end

    private

    def unpaid_cents
      AgentEarnings.new(store: @store, range: Time.current.beginning_of_month..Time.current).summary_for(@agent).unpaid
    end

    def pending_deductions
      AgentDeduction.pending.where(store: @store, user: @agent).order(:created_at, :id)
    end
  end
end
