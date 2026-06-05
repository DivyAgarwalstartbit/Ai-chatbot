class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :shop, null: false, foreign_key: true
      t.bigint :shopify_product_id
      t.string :title
      t.text :description
      t.string :handle
      t.decimal :price
      t.string :vendor
      t.string :image_url
      t.string :status
      t.jsonb :avaliability

      t.timestamps
    end
  end
end
