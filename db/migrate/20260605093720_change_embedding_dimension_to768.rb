# frozen_string_literal: true

# Change embedding column to 768 dimensions.
#
# Why 768?
#   - nomic-embed-text outputs 768-dim vectors natively.
#   - OpenAI text-embedding-3-small supports a `dimensions` parameter so we
#     can also request 768-dim vectors, keeping both providers compatible.
#   - Using the same dimension means you can switch providers without
#     invalidating stored embeddings (as long as you re-embed after switching).
class ChangeEmbeddingDimensionTo768 < ActiveRecord::Migration[8.1]
  def up
    # Drop the HNSW index first — indexes must be recreated when dimension changes.
    execute "DROP INDEX IF EXISTS index_document_chunks_on_embedding_hnsw;"

    change_column :document_chunks, :embedding, :vector, limit: 768

    execute <<~SQL
      CREATE INDEX index_document_chunks_on_embedding_hnsw
      ON document_chunks
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64);
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS index_document_chunks_on_embedding_hnsw;"
    change_column :document_chunks, :embedding, :vector, limit: 1536
    execute <<~SQL
      CREATE INDEX index_document_chunks_on_embedding_hnsw
      ON document_chunks
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64);
    SQL
  end
end
