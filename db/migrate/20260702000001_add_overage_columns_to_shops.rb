class AddOverageColumnsToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :usage_subscription_id, :string
    add_column :shops, :extra_conversations,   :integer, default: 0, null: false
    add_column :shops, :extra_tickets,         :integer, default: 0, null: false
    add_column :shops, :extra_documents,       :integer, default: 0, null: false
  end
end
