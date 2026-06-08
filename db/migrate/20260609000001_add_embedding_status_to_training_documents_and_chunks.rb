# frozen_string_literal: true

# Adds embedding lifecycle tracking to training_documents and document_chunks.
#
# training_documents.embedding_status  — tracks where the document is in the
#   embedding pipeline:
#     pending    → chunks exist but embedding has not been requested yet
#     processing → GenerateEmbeddingsJob is actively embedding chunks
#     completed  → all chunks have a non-null embedding vector
#     failed     → embedding failed (see embedding_error for details)
#
# training_documents.embedding_error   — stores the last embedding error message
#   so operators can diagnose failures without digging through logs.
#
# document_chunks.embedded_at          — timestamp set when an embedding is
#   successfully written. Allows fast queries for un-embedded chunks and
#   gives observability into when each chunk was last re-embedded.
#
class AddEmbeddingStatusToTrainingDocumentsAndChunks < ActiveRecord::Migration[8.1]
  def change
    # ── training_documents ──────────────────────────────────────────────────
    add_column :training_documents, :embedding_status, :string,
               default: "pending", null: false
    add_column :training_documents, :embedding_error, :text

    add_index :training_documents, :embedding_status,
              name: "index_training_documents_on_embedding_status"

    # ── document_chunks ─────────────────────────────────────────────────────
    add_column :document_chunks, :embedded_at, :datetime
  end
end
