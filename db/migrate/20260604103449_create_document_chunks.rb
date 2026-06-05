class CreateDocumentChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :document_chunks do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :training_document, null: false, foreign_key: true
      t.text :content
       t.vector :embedding

      t.timestamps
    end
  end
end
