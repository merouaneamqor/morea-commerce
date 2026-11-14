module Confirmations
  # What the welcome window of an agent says: their first name, the word of the day (one per day, the same all day) and, every MILESTONE_EVERY
  # orders they handled today, a message to keep them going. Scoped to the store and the signed-in agent.
  class AgentWelcome
    MILESTONE_EVERY = 100

    def initialize(store:, user:, today: DateRange.today)
      @store, @user, @today = store, user, today
    end

    def first_name = (@user.name.presence || @user.email).to_s.strip.split(/\s+/).first.to_s

    def word_of_the_day
      quotes = Array(I18n.t("agent_welcome.quotes"))
      quotes[@today.yday % quotes.size]
    end

    # Orders this agent recorded an outcome for since midnight (store time), each counted once.
    def handled_today
      @handled_today ||= ConfirmationAttempt.where(store: @store, user: @user, created_at: @today.in_time_zone(DateRange::ZONE).all_day).distinct.count(:order_confirmation_id)
    end

    # 1 for the first hundred, 2 for the second... 0 before the first.
    def milestone = handled_today / MILESTONE_EVERY

    def milestone_message
      return if milestone.zero?

      messages = Array(I18n.t("agent_welcome.milestones"))
      messages[(milestone - 1) % messages.size].gsub("%{count}", (milestone * MILESTONE_EVERY).to_s)
    end
  end
end
