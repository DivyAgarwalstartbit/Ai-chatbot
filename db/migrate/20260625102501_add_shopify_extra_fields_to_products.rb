class AddShopifyExtraFieldsToProducts < ActiveRecord::Migration[7.0]
  def change
    add_column :products, :product_type, :string
    add_column :products, :tags, :jsonb, default: []
    add_column :products, :collections_data, :jsonb, default: []
  end
end
