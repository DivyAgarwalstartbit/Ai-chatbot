class CreateShopOverageBundles < ActiveRecord::Migration[8.1]
  def change
    create_table :shop_overage_bundles do |t|
      t.references :shop, null: false, foreign_key: true
      t.string  :resource_type,           null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string  :shopify_usage_record_id
      t.datetime :charged_at,             null: false
      t.timestamps
    end

    add_index :shop_overage_bundles, [ :shop_id, :charged_at ]
  end
end
