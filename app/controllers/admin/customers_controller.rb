module Admin
  class CustomersController < BaseController
    PER_PAGE = 25
    # The seallo URLs say "risky"; the segment service says "at_risk".
    SEGMENT_PARAMS = { "loyal" => "loyal", "risky" => "at_risk", "at_risk" => "at_risk", "new" => "new" }.freeze

    before_action :set_customer, only: %i[show edit update]

    # Customers list in the seallo design: one phone number = one customer, filled by orders.
    def index
      @segments = Customers::Segments.new(current_store)
      @segment = SEGMENT_PARAMS[params[:segment].to_s]
      scope = current_store.customers
      # Customers with no order rows at all also count as new.
      scope = @segments.filter(scope, @segment) if @segment
      if params[:q].present?
        q = "%#{Customer.sanitize_sql_like(params[:q].strip)}%"
        scope = scope.where("customers.name ILIKE :q OR customers.phone ILIKE :q OR customers.email ILIKE :q OR customers.city ILIKE :q", q: q)
      end

      @total = scope.count
      @page = [ params[:page].to_i, 1 ].max
      @pages = [ (@total / PER_PAGE.to_f).ceil, 1 ].max
      @page = @pages if @page > @pages
      last_order = "(SELECT MAX(orders.created_at) FROM orders WHERE orders.customer_id = customers.id)"
      @customers = scope.order(Arel.sql("#{last_order} DESC NULLS LAST"), created_at: :desc).limit(PER_PAGE).offset((@page - 1) * PER_PAGE).load
      @segments.preload(@customers.map(&:id))
    end

    def show
      @orders = @customer.orders.recent
      @addresses = @customer.addresses.order(default: :desc, created_at: :desc)
    end

    def edit
    end

    def update
      if @customer.update(customer_params)
        redirect_to admin_customer_path(@customer), notice: "Customer updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_customer
      @customer = current_store.customers.find(params[:id])
    end

    def customer_params
      params.require(:customer).permit(:name, :email, :phone, :city)
    end
  end
end
