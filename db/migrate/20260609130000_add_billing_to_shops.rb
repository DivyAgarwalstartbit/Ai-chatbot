# frozen_string_literal: true

class AddBillingToShops < ActiveRecord::Migration[8.1]
  def change
    add_column :shops, :plan,      :string
    add_column :shops, :charge_id, :string
    add_column :shops, :paid,      :boolean, default: false, null: false
  end
end
