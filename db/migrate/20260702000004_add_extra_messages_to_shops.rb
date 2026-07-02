class AddExtraMessagesToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :extra_messages_per_conversation, :integer, default: 0, null: false
  end
end
