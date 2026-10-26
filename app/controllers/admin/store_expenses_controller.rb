module Admin
  class StoreExpensesController < BaseController
    before_action :require_workspace!

    def index
      @period = %w[30 90].include?(params[:period]) ? params[:period].to_i : 30
      @expense = current_store.store_expenses.new(spent_on: Date.current)
      load_expenses
    end

    def create
      @expense = current_store.store_expenses.new(params.require(:store_expense).permit(:spent_on, :category, :note))
      @expense.amount_cents = parse_mad_cents(params.require(:store_expense)[:amount])
      if @expense.save
        redirect_to admin_expenses_path, notice: "Expense recorded."
      else
        render_invalid(@expense.errors.full_messages.to_sentence)
      end
    rescue ArgumentError => e
      render_invalid(e.message)
    end

    def destroy
      current_store.store_expenses.find(params[:id]).destroy!
      redirect_to admin_expenses_path, notice: "Expense removed."
    end

    private

    def require_workspace!
      head :not_found unless current_store
    end

    def load_expenses
      @period ||= 30
      in_period = current_store.store_expenses.where(spent_on: (Date.current - (@period - 1))..Date.current)
      @total_cents = in_period.sum(:amount_cents)
      @expenses = in_period.recent.limit(200)
    end

    def render_invalid(message)
      @period = 30
      @error = message
      load_expenses
      render :index, status: :unprocessable_entity
    end
  end
end
