class UpdateAiShopperConfigurations < ActiveRecord::Migration[8.1]
  def change
        remove_column :ai_shopper_configurations, :language
    remove_column :ai_shopper_configurations, :default_queries

    add_column :ai_shopper_configurations, :store_details, :jsonb, default: {}, null: false
  end
end
