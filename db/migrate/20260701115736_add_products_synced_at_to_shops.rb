class AddProductsSyncedAtToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :products_synced_at, :datetime
  end
end
