module Admin
  class DiscountsController < BaseController
    before_action :set_discount, only: %i[edit update destroy]

    def index
      @discounts = current_store.discounts.order(active: :desc, code: :asc)
    end

    def new
      @discount = current_store.discounts.new(discount_type: "percent", active: true)
    end

    def create
      @discount = current_store.discounts.new(discount_params)
      if @discount.save
        redirect_to admin_discounts_path, notice: "Discount created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @discount.update(discount_params)
        redirect_to admin_discounts_path, notice: "Discount saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @discount.destroy!
      redirect_to admin_discounts_path, notice: "Discount deleted."
    end

    private

    def set_discount
      @discount = current_store.discounts.find(params[:id])
    end

    def discount_params
      params.require(:discount).permit(:code, :discount_type, :value, :active, :starts_at, :ends_at)
    end
  end
end
