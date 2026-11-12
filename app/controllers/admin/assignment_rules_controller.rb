module Admin
  # "Règles d'attribution": who gets the orders that come in, and what happens when an agent is too slow. Owners and supervisors only (the
  # confirmation agents are kept out of this controller by BaseController#confine_confirmation_agents!).
  # How the rules are applied is in Confirmations::AssignmentRunner.
  class AssignmentRulesController < BaseController
    before_action :require_store_context!
    before_action :set_rule, only: %i[edit update destroy toggle move]
    helper_method :agents, :sources

    def index
      @rules = current_store.assignment_rules.includes(assignment_rule_agents: :user).to_a
    end

    def new
      @rule = current_store.assignment_rules.new(distribution: "equal", timeout_minutes: 30, transfer_on_timeout: true, active: true)
      render_form
    end

    def create
      @rule = current_store.assignment_rules.new
      save_rule ? redirect_to(admin_assignment_rules_path, notice: t("assignment_rules.created")) : render_form(status: :unprocessable_content)
    end

    def edit
      render_form
    end

    def update
      save_rule ? redirect_to(admin_assignment_rules_path, notice: t("assignment_rules.saved")) : render_form(status: :unprocessable_content)
    end

    def destroy
      @rule.destroy!
      redirect_to admin_assignment_rules_path, notice: t("assignment_rules.deleted")
    end

    def toggle
      @rule.update!(active: !@rule.active)
      redirect_to admin_assignment_rules_path, notice: t(@rule.active ? "assignment_rules.switched_on" : "assignment_rules.switched_off", name: @rule.name)
    end

    # Priority: the arrows swap a rule with its neighbour; the first matching rule decides.
    def move
      rules = current_store.assignment_rules.to_a
      index = rules.index(@rule)
      neighbour = params[:direction] == "up" ? index - 1 : index + 1
      if index && neighbour >= 0 && neighbour < rules.size
        rules[index], rules[neighbour] = rules[neighbour], rules[index]
        AssignmentRule.transaction { rules.each_with_index { |rule, position| rule.update_columns(position: position + 1) } }
      end
      redirect_to admin_assignment_rules_path
    end

    private

    def require_store_context!
      head :not_found unless current_store
    end

    def set_rule
      @rule = current_store.assignment_rules.includes(assignment_rule_agents: :user).find(params[:id])
    end

    def agents
      @agents ||= current_store.users.active.where(confirmation_role: "agent").order(:name, :id).to_a
    end

    # [["Manuelle", "manual"], ["Boutique Shopify", "12"], ...]: what a rule can be limited to.
    def sources
      @sources ||= [ [ t("assignment_rules.manual_source"), "manual" ] ] + current_store.store_connections.order(:name).pluck(:name, :id).map { |name, id| [ name, id.to_s ] }
    end

    def render_form(status: :ok)
      render(turbo_frame_request? ? :form : :form_page, layout: !turbo_frame_request?, status: status)
    end

    # Sets the rule from the form. Amounts are typed in MAD; the agents are the ticked ones (only agents of this store are taken), each with
    # her percentage when the rule splits by percentage.
    def save_rule
      form = params.require(:assignment_rule)
      attrs = form.permit(:name, :description, :distribution, :timeout_minutes, :transfer_on_timeout, :active).to_h
      problems = []
      %i[min_amount max_amount].each do |key|
        value = form[key].to_s.strip
        attrs["#{key}_cents"] = value.blank? ? nil : parse_cents(value, problems)
      end
      attrs["sources"] = form[:sources_mode] == "chosen" ? Array(form[:sources]) & sources.map(&:last) : []
      @rule.assign_attributes(attrs)
      apply_agents(Array(form[:agent_ids]), form[:percents].respond_to?(:to_unsafe_h) ? form[:percents].to_unsafe_h : {})
      problems.each { |message| @rule.errors.add(:base, message) }
      return false if problems.any?

      @rule.save
    end

    def parse_cents(value, problems)
      parse_mad_cents(value)
    rescue ArgumentError => e
      problems << e.message
      nil
    end

    def apply_agents(ids, percents)
      chosen = agents.map(&:id) & ids.map(&:to_i)
      @rule.assignment_rule_agents.each { |row| row.mark_for_destruction unless chosen.include?(row.user_id) }
      chosen.each do |user_id|
        row = @rule.assignment_rule_agents.find { |existing| existing.user_id == user_id } || @rule.assignment_rule_agents.build(user_id: user_id)
        row.percent = @rule.percent? ? percents[user_id.to_s].presence&.to_i : nil
      end
    end
  end
end
