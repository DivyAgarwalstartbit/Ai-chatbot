# frozen_string_literal: true

# Splits a TrainingDocument's content into chunks and stores them in
# document_chunks. Triggered automatically by the after_save callback on
# TrainingDocument whenever content or shopify_content changes.
#
# After chunking succeeds, enqueues GenerateEmbeddingsJob so all new chunks
# receive pgvector embeddings. This closes the full indexing pipeline:
#
#   content saved
#     → DocumentChunkJob   (this job)
#       → ChunkDocumentService  (delete old chunks, insert new)
#         → GenerateEmbeddingsJob  (embed every chunk)
#
class DocumentChunkJob < ApplicationJob
  queue_as :documents

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  # @param document_id [Integer] ID of the TrainingDocument to chunk.
  def perform(document_id)
    document = TrainingDocument.find_by(id: document_id)

    unless document
      Rails.logger.warn("[DocumentChunkJob] TrainingDocument ##{document_id} not found, skipping.")
      return
    end

    # Build the full text to chunk. For policy documents this combines manual
    # content AND Shopify-synced content so both sources are searchable.
    text = combined_content(document)

    if text.blank?
      Rails.logger.warn("[DocumentChunkJob] TrainingDocument ##{document_id} has no content, skipping.")
      return
    end

    # If the document's content field doesn't yet reflect the combined text
    # (e.g. triggered by a shopify_content change), we chunk from a temporary
    # in-memory document so we don't overwrite the original content column.
    target = document_with_combined_content(document, text)

    count = ChunkDocumentService.new(target).call

    Rails.logger.info("[DocumentChunkJob] Document ##{document_id} split into #{count} chunk(s).")

    # Reset embedding status so GenerateEmbeddingsJob starts fresh.
    document.update_columns(embedding_status: "pending", embedding_error: nil)

    # Enqueue embedding generation for all the newly created chunks.
    GenerateEmbeddingsJob.perform_later(document_id)
  end

  private

  # Returns the text that should actually be chunked and embedded.
  # Policy documents combine manual entry + Shopify-synced content so both
  # sources are represented in the vector index.
  def combined_content(document)
    parts = [document.content.presence, document.shopify_content.presence].compact
    parts.join("\n\n").strip
  end

  # Returns a document-like object carrying the combined text for chunking.
  # We use the real document when its content matches, otherwise wrap it in a
  # lightweight struct so ChunkDocumentService doesn't need to know about the
  # dual-content model.
  def document_with_combined_content(document, text)
    return document if document.content.to_s.strip == text

    # Delegate all AR calls to the real document but override #content.
    DocumentProxy.new(document, text)
  end

  # Minimal proxy so ChunkDocumentService (which reads doc.content, doc.id,
  # doc.shop_id, and doc.document_chunks) can work with combined text without
  # mutating the persisted record.
  DocumentProxy = Struct.new(:document, :content) do
    delegate :id, :shop_id, :document_chunks, to: :document
  end
end
