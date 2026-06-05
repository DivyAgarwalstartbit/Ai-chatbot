class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.references :shop, null: false, foreign_key: true
      t.bigint :shopify_customer_id
      t.string :first_name
      t.string :last_name
      t.string :email
      t.string :phone
      t.string :visitor_id

      t.timestamps
    end
  end
end
