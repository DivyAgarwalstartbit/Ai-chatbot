class CreateAiShopperConfigurations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_shopper_configurations do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :assistant_avatar_url
      t.string :assistant_name
      t.string :brand_tone
      t.text :greeting
      t.jsonb :default_queries
      t.string :language
      t.jsonb :starter_prompts
      t.jsonb :sync_state
      t.jsonb :visibility_rules
      t.boolean :widget_enabled
      t.jsonb :widget_settings

      t.timestamps
    end
  end
end
