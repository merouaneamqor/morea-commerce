# frozen_string_literal: true

class AddSizeChartToProducts < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :size_chart, :jsonb, default: {}, null: false
  end
end
