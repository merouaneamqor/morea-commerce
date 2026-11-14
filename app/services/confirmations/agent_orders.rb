module Confirmations
  # The orders a confirmation agent may see: never what a colleague holds or was given; and, once the owner has an active attribution rule,
  # only what the rules gave them, what they hold or what they already confirmed. Without a rule the open pool is shared. Scoped to the store.
  class AgentOrders
    def initialize(store:, user:)
      @store, @user = store, user
    end

    def scope
      held_by_others = OrderConfirmation.where(store: @store).where.not(assigned_user_id: [ nil, @user.id ]).select(:order_id)
      attributed_to_others = OrderConfirmation.where(store: @store).where.not(attributed_user_id: [ nil, @user.id ]).select(:order_id)
      orders = @store.orders.where.not(id: held_by_others).where.not(id: attributed_to_others)
      return orders unless @store.assignment_enforced?

      given = OrderConfirmation.where(store: @store).where("attributed_user_id = :user OR assigned_user_id = :user", user: @user.id).select(:order_id)
      confirmed = ConfirmationAttempt.joins(:order_confirmation).where(store: @store, user: @user, outcome: "confirmed").select("order_confirmations.order_id")
      orders.where(id: given).or(orders.where(id: confirmed))
    end

    # Newest first; a search looks at the number, the customer's name and phone.
    def search(query, limit: 25)
      orders = scope.includes(:order_confirmation).order(created_at: :desc, id: :desc)
      term = query.to_s.strip
      if term.present?
        like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        orders = orders.where("orders.number ILIKE :like OR orders.customer_name ILIKE :like OR orders.customer_phone ILIKE :like", like: like)
      end
      orders.limit(limit).to_a
    end
  end
end
