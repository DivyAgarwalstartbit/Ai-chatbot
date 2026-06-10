# frozen_string_literal: true

# Set the embedding column to the correct dimension for text-embedding-3-small (1536)
# and add an HNSW index for fast approximate nearest-neighbour search.
class ChangeEmbeddingColumnDimensionAndAddHnswIndex < ActiveRecord::Migration[8.1]
  def up
    # Re-create the column with an explicit 1536-dimension type.
    # The original column was created without a dimension, so pgvector treated it
    # as an unconstrained vector. We change it to enforce the correct size.
    change_column :document_chunks, :embedding, :vector, limit: 768

    # HNSW index using cosine distance — matches the cosine_similarity query we'll
    # use during retrieval.
    execute <<~SQL
      CREATE INDEX index_document_chunks_on_embedding_hnsw
      ON document_chunks
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64);
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_document_chunks_on_embedding_hnsw;"
    change_column :document_chunks, :embedding, :vector
  end
end
