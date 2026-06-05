class CreateTrainingDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :training_documents do |t|
      t.references :shop, null: false, foreign_key: true
      t.string :title
      t.string :document_type
      t.text :content

      t.timestamps
    end
  end
end
