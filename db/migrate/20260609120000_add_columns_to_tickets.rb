# frozen_string_literal: true

class AddColumnsToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column    :tickets, :customer_id,     :bigint
    add_column    :tickets, :conversation_id, :bigint
    add_column    :tickets, :source,          :string
    add_column    :tickets, :priority,        :string, default: "normal"

    change_column_default :tickets, :status, from: nil, to: "open"

    add_index :tickets, :customer_id
    add_index :tickets, :conversation_id
    add_index :tickets, %i[shop_id status]

    add_foreign_key :tickets, :customers
    add_foreign_key :tickets, :conversations
  end
end
