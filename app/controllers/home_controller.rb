class HomeController < ApplicationController
  def index
    @store = current_store
    @store&.translations&.load if @store
    @sections = @store ? @store.home_sections_for_display : []
  end
end
