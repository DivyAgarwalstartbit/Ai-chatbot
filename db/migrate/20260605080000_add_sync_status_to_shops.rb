class AddSyncStatusToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :sync_status, :string, default: "idle", null: false
  end
end
