class PagesController < ApplicationController
  before_action :require_store!

  def show
    @page = current_store.pages.published.includes(:translations).find_by!(slug: params[:slug])
  end
end
