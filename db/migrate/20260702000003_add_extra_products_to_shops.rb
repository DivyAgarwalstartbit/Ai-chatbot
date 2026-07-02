class AddExtraProductsToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :extra_products, :integer, default: 0, null: false
  end
end
