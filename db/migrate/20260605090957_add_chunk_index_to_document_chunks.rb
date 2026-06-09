class AddChunkIndexToDocumentChunks < ActiveRecord::Migration[8.1]
  def change
    add_column :document_chunks, :chunk_index, :integer
    add_index  :document_chunks, %i[training_document_id chunk_index],
               name: "index_document_chunks_on_doc_and_chunk_index"
  end
end
