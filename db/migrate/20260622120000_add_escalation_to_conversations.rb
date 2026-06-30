class AddEscalationToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversations, :handoff_mode, :boolean, default: false, null: false
    add_column :conversations, :escalated_at, :datetime
  end
end
