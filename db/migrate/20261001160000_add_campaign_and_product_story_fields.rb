class AddCampaignAndProductStoryFields < ActiveRecord::Migration[8.1]
  def change
    change_table :stores, bulk: true do |t|
      t.string :campaign_title
      t.string :campaign_season
      t.string :campaign_image_url
      t.string :campaign_cta
    end

    change_table :products, bulk: true do |t|
      t.text :fit
      t.text :movement
    end
  end
end
