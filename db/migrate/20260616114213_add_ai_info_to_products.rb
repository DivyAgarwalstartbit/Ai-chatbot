class AddAiInfoToProducts < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :ai_info, :text
  end
end
