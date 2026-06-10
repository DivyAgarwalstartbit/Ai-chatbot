class CreateProductVariants < ActiveRecord::Migration[8.1]
  def change
    create_table :product_variants do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.bigint :shopify_variant_id
      t.string :title
      t.string :sku
      t.decimal :price
      t.decimal :compare_at_price
      t.integer :inventory_quantity
      t.string :inventory_policy
      t.boolean :available
      t.jsonb :options

      t.timestamps
    end
  end
end
