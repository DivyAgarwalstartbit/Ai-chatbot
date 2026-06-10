# frozen_string_literal: true

# Generates and stores OpenAI embeddings for DocumentChunk records.
#
# Can be enqueued in two modes:
#
#   # Single chunk
#   EmbeddingJob.perform_later(chunk_id: 42)
#
#   # All un-embedded chunks for a training document
#   EmbeddingJob.perform_later(training_document_id: 7)
#
# Retry behaviour:
#   - Rate limit errors (429): waits 60 s before retrying, up to 5 times.
#   - Other API errors: waits 10 s before retrying, up to 3 times.
#   - Both exhaustion paths are handled by the discard_on / retry_on blocks.
#
class EmbeddingJob < ApplicationJob
  queue_as :embeddings

  # Rate-limit: generous back-off, 5 attempts total.
  retry_on Ai::EmbeddingService::RateLimitError,
           wait: 60.seconds,
           attempts: 5

  # Generic API errors: short back-off, 3 attempts total.
  retry_on Ai::EmbeddingService::ApiError,
           wait: 10.seconds,
           attempts: 3

  # Bad API key / misconfiguration — retrying won't help; discard immediately
  # and surface the error to the log so an operator can fix the key.
  discard_on Ai::EmbeddingService::AuthenticationError do |job, error|
    Rails.logger.error(
      "[EmbeddingJob] Authentication failed — check OPENAI_API_KEY. " \
      "Job args: #{job.arguments.inspect}. Error: #{error.message}"
    )
  end

  # @param chunk_id [Integer, nil]          Embed a single chunk.
  # @param training_document_id [Integer, nil] Embed all pending chunks for a document.
  def perform(chunk_id: nil, training_document_id: nil)
    chunks = resolve_chunks(chunk_id:, training_document_id:)
    return if chunks.empty?

    service = Ai::EmbeddingService.new

    # Process in batches of 100 to stay well within OpenAI's 2048-input limit
    # while keeping the number of API round-trips low.
    chunks.each_slice(100) do |batch|
      texts = batch.map { |c| truncate_text(c.content) }

      vectors = service.embed_batch(texts)

      now = Time.current

      batch.zip(vectors).each do |chunk, vector|
        chunk.update_columns(
          embedding:   vector,
          embedded_at: now,
          updated_at:  now
        )
      end

      Rails.logger.info(
        "[EmbeddingJob] Embedded #{batch.size} chunk(s). " \
        "IDs: #{batch.map(&:id).inspect}"
      )
    end
  end

  private

  def resolve_chunks(chunk_id:, training_document_id:)
    if chunk_id.present?
      chunk = DocumentChunk.find_by(id: chunk_id)
      unless chunk
        Rails.logger.warn("[EmbeddingJob] DocumentChunk #{chunk_id} not found, skipping.")
        return []
      end
      [chunk]
    elsif training_document_id.present?
      DocumentChunk
        .without_embedding
        .where(training_document_id:)
        .to_a
        .tap do |chunks|
          if chunks.empty?
            Rails.logger.info(
              "[EmbeddingJob] No pending chunks for TrainingDocument " \
              "#{training_document_id}."
            )
          end
        end
    else
      Rails.logger.warn("[EmbeddingJob] Called with no arguments, skipping.")
      []
    end
  end

  # OpenAI's text-embedding-3-small supports up to 8191 tokens.
  # Roughly 4 chars per token → ~32 000 chars. We truncate at 30 000 chars
  # to stay safely under the limit without an actual tokeniser dependency.
  MAX_CHARS = 30_000

  def truncate_text(text)
    text.length > MAX_CHARS ? text[0, MAX_CHARS] : text
  end
end
