class AddSourceToDocumentChunks < ActiveRecord::Migration[8.1]
  def change
    add_column :document_chunks,
               :source_type,
               :string

    add_column :document_chunks,
               :source_id,
               :bigint


    change_column_null(
      :document_chunks,
      :training_document_id,
      true
    )


    add_index :document_chunks,
              [
               :source_type,
               :source_id
              ]
  end
end
