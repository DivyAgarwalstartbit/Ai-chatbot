class AddCustomerToConversations < ActiveRecord::Migration[8.1]
  def change
    add_reference :conversations, :customer, null: false, foreign_key: true
  end
end
