module Confirmations
  # Applies the attribution rules of a store. Run every minute by AssignmentRulesJob.
  #
  # 1. New orders: every order waiting for a call and not attributed yet goes to the first ACTIVE rule (in priority order) that matches it
  #    (amount range, sources). The rule picks one of its agents who is ONLINE (a shift is open) and under capacity. The split is fair over the
  #    shop day: equal = the same share each (50/50 with two agents), percent = the share the rule gives each agent (70/30...). The agent who is
  #    furthest below her share gets the order. Nobody online: the order stays open to every agent.
  # 2. Late orders: an order a rule attributed is taken away from the agent when she has not confirmed it within the rule's delay (30 minutes
  #    by default) and given to another agent who is active and online: first another agent of the same rule, else any other agent online.
  #    Nobody else online: it stays where it is. Orders with a callback planned, a call in progress or a blocked / wrong number are left alone.
  #
  # Hand attributions (no rule) never move by themselves.
  class AssignmentRunner
    CAPACITY = Assignments::CAPACITY

    def self.run_all!(now: Time.current)
      Store.where(id: AssignmentRule.active.select(:store_id)).find_each { |store| new(store: store, now: now).run! }
    end

    # random: only for the "random" method (a seeded Random makes it repeatable in tests).
    def initialize(store:, now: Time.current, random: Random.new)
      @store, @now, @random = store, now, random
    end

    # { attributed: n, transferred: n }
    def run!
      rules = @store.assignment_rules.active.includes(assignment_rule_agents: :user).to_a
      return { attributed: 0, transferred: 0 } if rules.empty?

      { attributed: attribute_new!(rules), transferred: transfer_late! }
    end

    private

    def attribute_new!(rules)
      orders = assignments.waiting_scope.where("order_confirmations.attributed_user_id IS NULL")
        .where("order_confirmations.disposition IS NULL OR order_confirmations.disposition IN ('pending', 'no_answer')")
        .preload(:order_confirmation, external_order_receipt: :store_connection).order(:created_at, :id).to_a
      done = 0
      orders.each do |order|
        rule = rules.find { |candidate| candidate.matches?(order, source_key: source_key(order)) }
        next unless rule

        agent = pick(rule)
        next unless agent

        give!(order, agent, rule, "Assigned to #{label(agent)} by the rule “#{rule.name}”")
        done += 1
      end
      done
    end

    def transfer_late!
      late.filter_map do |confirmation|
        confirmation.with_lock do
          rule = confirmation.assignment_rule
          current = confirmation.attributed_user
          next unless rule && current && confirmation.attributed_at && confirmation.attributed_at <= @now - rule.timeout_minutes.minutes

          agent = pick(rule, except: current) || fallback(except: current)
          next unless agent

          give!(confirmation.order, agent, rule, "Moved from #{label(current)} to #{label(agent)}: not confirmed within #{rule.timeout_minutes} minutes")
          true
        end
      end.size
    end

    # Orders attributed by a rule whose delay is over (the rule may be switched off or edited since: only active rules with the transfer on).
    def late
      OrderConfirmation.joins(:order, :assignment_rule).where(store_id: @store.id).where.not(attributed_user_id: nil)
        .where(assignment_rules: { active: true, transfer_on_timeout: true })
        .where("order_confirmations.attributed_at <= ?::timestamp - (assignment_rules.timeout_minutes * INTERVAL '1 minute')", @now)
        .where(orders: { status: "new", archived_at: nil, sendit_code: [ nil, "" ] })
        .where(disposition: %w[pending no_answer], call_started_at: nil)
        .includes(:order, :assignment_rule, :attributed_user).order(:attributed_at, :id).to_a
    end

    # The agent the rule picks among its agents who are online, under capacity and good enough (the rule's minimum success rate; an agent who made
    # no call yet has no rate and stays eligible):
    # - equal / percent: the agent furthest below her share today, smallest (orders given today / weight);
    # - least_loaded: the fewest waiting orders; best_performance: the best success rate (fewest waiting orders on a tie); random: any of them.
    def pick(rule, except: nil)
      weights = rule.weights
      eligible = rule.assignment_rule_agents.map(&:user).select do |user|
        weights[user.id].to_i.positive? && user != except && usable?(user) && good_enough?(rule, user)
      end
      case rule.distribution
      when "least_loaded" then eligible.min_by { |user| [ loads[user.id].to_i, user.id ] }
      when "best_performance" then eligible.max_by { |user| [ assignments.success_rates[user.id] || -1, -loads[user.id].to_i, -user.id ] }
      when "random" then eligible.sample(random: @random)
      else eligible.min_by { |user| [ shares[[ rule.id, user.id ]].to_f / weights[user.id], user.id ] }
      end
    end

    def good_enough?(rule, user)
      rate = assignments.success_rates[user.id]
      !rule.min_success? || rate.nil? || rate >= rule.min_success_percent
    end

    # Any other agent online and under capacity, the least loaded first.
    def fallback(except:)
      assignments.agents.select { |user| user != except && usable?(user) }.min_by { |user| [ loads[user.id].to_i, user.id ] }
    end

    def usable?(user)
      user.active? && user.confirmation_role == "agent" && assignments.on_shift?(user) && loads[user.id].to_i < CAPACITY
    end

    def give!(order, agent, rule, note)
      confirmation = OrderConfirmation.find_or_create_by!(order: order) { |row| row.store = @store }
      attrs = { attributed_user: agent, attributed_at: @now, assignment_rule: rule }
      attrs.merge!(assigned_user: nil, claimed_at: nil, call_started_at: nil, last_activity_at: nil) if confirmation.assigned_user_id && confirmation.assigned_user_id != agent.id
      previous = confirmation.attributed_user_id
      confirmation.update!(attrs)
      order.record_event!("comment", body: note)
      loads[previous] = [ loads[previous].to_i - 1, 0 ].max if previous
      loads[agent.id] = loads[agent.id].to_i + 1
      shares[[ rule.id, agent.id ]] += 1
    end

    def label(user) = user.name.presence || user.email
    def source_key(order) = order.external_order_receipt&.store_connection_id&.to_s || "manual"

    def assignments = @assignments ||= Assignments.new(store: @store)

    # Waiting orders attributed to each agent now (her load).
    def loads = @loads ||= assignments.loads.dup

    # How many orders each rule gave each agent since the shop day began: { [rule id, user id] => n }
    def shares
      @shares ||= Hash.new(0).tap do |counts|
        day_start = @now.in_time_zone(DateRange::ZONE).beginning_of_day
        OrderConfirmation.where(store_id: @store.id).where.not(assignment_rule_id: nil).where("attributed_at >= ?", day_start)
          .group(:assignment_rule_id, :attributed_user_id).count.each { |key, count| counts[key] = count }
      end
    end
  end
end
