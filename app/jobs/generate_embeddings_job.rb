# frozen_string_literal: true

# Generates pgvector embeddings for all chunks of a TrainingDocument.
#
# Enqueued automatically by DocumentChunkJob after chunking completes.
# Also enqueued by the indexing pipeline whenever knowledge-base content
# changes (policy saves, FAQ saves, Shopify sync, document uploads).
#
# Pipeline position:
#   ProcessDocumentJob (file upload only)
#     → [after_save :content] → DocumentChunkJob
#                                 → GenerateEmbeddingsJob  ← this job
#
# For manual / synced content that writes directly to training_documents:
#   Controller saves training_document
#     → [after_save :content or :shopify_content] → DocumentChunkJob
#                                                      → GenerateEmbeddingsJob
#
# Retry strategy (Solid Queue):
#   Rate limit (429)    : wait 60 s, up to 5 total attempts
#   Generic API error   : wait 10 s, up to 3 total attempts
#   Auth error (bad key): discard immediately, log — retrying won't help
#   Any other error     : wait polynomially, up to 3 total attempts
#
class GenerateEmbeddingsJob < ApplicationJob
  queue_as :embeddings

  # Rate-limit back-off — generous wait because the quota window is typically 1 min.
  retry_on Ai::EmbeddingService::RateLimitError,
           wait: 60.seconds,
           attempts: 5

  # Transient API errors — short back-off.
  retry_on Ai::EmbeddingService::ApiError,
           wait: 10.seconds,
           attempts: 3

  # Misconfigured key — retrying is pointless; surface the error immediately.
  discard_on Ai::EmbeddingService::AuthenticationError do |job, error|
    document_id = job.arguments.first
    Rails.logger.error(
      "[GenerateEmbeddingsJob] Authentication failed — check EMBEDDING_PROVIDER " \
      "and the relevant API key. Document ##{document_id}. Error: #{error.message}"
    )
    # Mark the document so the merchant can see it failed, not just silently stall.
    TrainingDocument.find_by(id: document_id)&.update_columns(
      embedding_status: "failed",
      embedding_error:  "Authentication failed: #{error.message.truncate(400)}"
    )
  end

  # Catch-all for unexpected errors (network blips, DB timeouts, etc.)
  retry_on StandardError,
           wait: :polynomially_longer,
           attempts: 3

  # @param document_id [Integer] ID of the TrainingDocument whose chunks need embedding.
  def perform(document_id)
    document = TrainingDocument.find_by(id: document_id)

    unless document
      Rails.logger.warn(
        "[GenerateEmbeddingsJob] TrainingDocument ##{document_id} not found — discarding."
      )
      return
    end

    Rails.logger.info(
      "[GenerateEmbeddingsJob] Starting embedding for Document ##{document_id} " \
      "(#{document.document_type}, #{document.title.presence || 'untitled'})."
    )

    result = Ai::EmbeddingGenerationService.new(document).call

    if result.success?
      Rails.logger.info(
        "[GenerateEmbeddingsJob] Document ##{document_id} — " \
        "#{result.chunks_embedded} chunk(s) embedded successfully."
      )
    else
      # EmbeddingGenerationService already marked the document as failed and logged.
      # Re-raise so retry_on can handle transient failures.
      raise Ai::EmbeddingService::ApiError, result.error
    end
  end
end
