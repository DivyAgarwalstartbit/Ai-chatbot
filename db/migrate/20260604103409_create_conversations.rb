class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|

      t.references :shop,
                   null: false,
                   foreign_key: true

      t.references :customer,
                   null: true,
                   foreign_key: true


      # browser/session tracking
      t.string :session_id,
               null: false


      # active, resolved, escalated
      t.string :status,
               default: "active"


      # widget, whatsapp, email etc
      t.string :source,
               default: "widget"


      # AI solved or human needed
      t.boolean :ai_resolved,
                default: false


      t.datetime :started_at

      t.datetime :ended_at

      t.integer :message_count,
                default: 0


      t.timestamps
    end


    add_index :conversations,
              [:shop_id, :session_id]

    add_index :conversations,
              :status
  end
end