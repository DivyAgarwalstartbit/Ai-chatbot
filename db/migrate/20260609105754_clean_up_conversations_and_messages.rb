# frozen_string_literal: true

class CleanUpConversationsAndMessages < ActiveRecord::Migration[8.1]
  def change
    # Remove stale columns that belong on messages, not conversations
    remove_column :conversations, :role, :string
    remove_column :conversations, :message, :integer

    # Make customer_id nullable — anonymous visitors are the common case
    change_column_null :conversations, :customer_id, true

    # Add conversation metadata
    add_column :conversations, :status,          :string,   default: "open"
    add_column :conversations, :last_message_at, :datetime
    add_column :conversations, :page_url,        :string
    add_column :conversations, :reviewed_at,     :datetime

    # Add message metadata for AI source citations and token tracking
    add_column :messages, :metadata, :jsonb
  end
end
