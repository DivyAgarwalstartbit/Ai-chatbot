class CreateSolidCableMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages, force: false, if_not_exists: true do |t|
      t.binary  :channel,      null: false
      t.bigint  :channel_hash, null: false
      t.binary  :payload,      null: false
      t.datetime :created_at,  null: false
    end

    add_index :solid_cable_messages, :channel,      if_not_exists: true
    add_index :solid_cable_messages, :channel_hash, if_not_exists: true
    add_index :solid_cable_messages, :created_at,   if_not_exists: true
  end
end