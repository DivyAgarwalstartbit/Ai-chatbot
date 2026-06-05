class CreateTickets < ActiveRecord::Migration[8.1]
  def change
    create_table :tickets do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :issue
      t.string :status
      t.string :subject

      t.timestamps
    end
  end
end
