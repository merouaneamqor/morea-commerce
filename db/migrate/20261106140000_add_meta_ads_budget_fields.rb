# frozen_string_literal: true

# Read-only campaign / ad set budgets and delivery status from Meta (ads_read).
# Amounts are the account currency in major units (Meta's minor units ÷ offset).
class AddMetaAdsBudgetFields < ActiveRecord::Migration[8.0]
  def change
    change_table :meta_ads_campaigns, bulk: true do |t|
      t.decimal :daily_budget, precision: 18, scale: 4
      t.decimal :lifetime_budget, precision: 18, scale: 4
      t.decimal :budget_remaining, precision: 18, scale: 4
      t.decimal :spend_cap, precision: 18, scale: 4
    end

    change_table :meta_ads_ad_sets, bulk: true do |t|
      t.decimal :daily_budget, precision: 18, scale: 4
      t.decimal :lifetime_budget, precision: 18, scale: 4
      t.decimal :budget_remaining, precision: 18, scale: 4
    end

    add_check_constraint :meta_ads_campaigns,
      "(daily_budget IS NULL OR daily_budget >= 0) AND (lifetime_budget IS NULL OR lifetime_budget >= 0) AND (budget_remaining IS NULL OR budget_remaining >= 0) AND (spend_cap IS NULL OR spend_cap >= 0)",
      name: "meta_ads_campaigns_budgets_non_negative"
    add_check_constraint :meta_ads_ad_sets,
      "(daily_budget IS NULL OR daily_budget >= 0) AND (lifetime_budget IS NULL OR lifetime_budget >= 0) AND (budget_remaining IS NULL OR budget_remaining >= 0)",
      name: "meta_ads_ad_sets_budgets_non_negative"
  end
end
