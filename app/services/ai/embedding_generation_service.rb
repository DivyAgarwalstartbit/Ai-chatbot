# frozen_string_literal: true

module Ai
  # Generates and persists pgvector embeddings for all chunks belonging to one
  # TrainingDocument.
  #
  # Responsibilities:
  #   - Load every DocumentChunk for the document (ordered by chunk_index)
  #   - Embed them in batches via Ai::EmbeddingService
  #   - Update the existing chunks with embedding vectors + embedded_at timestamp
  #   - Update training_documents.embedding_status throughout the run
  #
  # Called by GenerateEmbeddingsJob. Never call directly from a web request.
  #
  # Usage:
  #   result = Ai::EmbeddingGenerationService.new(training_document).call
  #   result.success?         # => true / false
  #   result.chunks_embedded  # => Integer count on success
  #   result.error            # => String on failure, nil on success
  #
  class EmbeddingGenerationService
    # How many chunk texts we send to the embedding provider in one API call.
    # Nomic/Ollama handles large batches fine; OpenAI limit is 2048 inputs.
    BATCH_SIZE = 50

    # Truncate chunk text at this many characters before embedding.
    # ~4 chars/token → 32 000 chars ≈ 8 000 tokens, safely under both providers.
    MAX_CHARS = 30_000

    Result = Struct.new(:chunks_embedded, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def initialize(document)
      @document = document
    end

    def call
      chunks = @document.document_chunks.order(:chunk_index).to_a

      if chunks.empty?
        Rails.logger.info(
          "[EmbeddingGenerationService] Document ##{@document.id} has no chunks — skipping."
        )
        mark_completed!(0)
        return Result.new(chunks_embedded: 0, error: nil)
      end

      mark_processing!

      service = Ai::EmbeddingService.new
      embedded_count = 0

      chunks.each_slice(BATCH_SIZE) do |batch|
        texts   = batch.map { |c| truncate(c.content) }
        vectors = service.embed_batch(texts)

        now = Time.current

        # Guard against a race where a later DocumentChunkJob deleted and
        # recreated these chunks between our initial fetch and this upsert.
        # upsert_all falls back to INSERT when the id is missing, which fails
        # the NOT NULL constraint on shop_id. Only update rows that still exist.
        existing_ids = DocumentChunk.where(id: batch.map(&:id)).pluck(:id).to_set

        rows = batch.zip(vectors).filter_map do |chunk, vector|
          next unless existing_ids.include?(chunk.id)
          { id: chunk.id, embedding: vector, embedded_at: now }
        end

        next if rows.empty?

            # update_only must NOT include updated_at — Rails adds it automatically
            # via the record_timestamps mechanism. Including it explicitly causes
            # PG::SyntaxError "multiple assignments to same column".
            rows.each do |row|
      DocumentChunk
        .where(id: row[:id])
        .update_all(
          embedding: row[:embedding],
          embedded_at: row[:embedded_at]
        )
    end
        embedded_count += batch.size

        Rails.logger.info(
          "[EmbeddingGenerationService] Document ##{@document.id}: " \
          "embedded #{embedded_count}/#{chunks.size} chunks."
        )
      end

      mark_completed!(embedded_count)
      Result.new(chunks_embedded: embedded_count, error: nil)

    rescue Ai::EmbeddingService::RateLimitError => e
      message = "Rate limit reached: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} #{message}")
      mark_failed!(message)
      Result.new(chunks_embedded: 0, error: message)

    rescue Ai::EmbeddingService::AuthenticationError => e
      message = "Authentication failed: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} #{message}")
      mark_failed!(message)
      Result.new(chunks_embedded: 0, error: message)

    rescue Ai::EmbeddingService::ApiError => e
      message = "API error: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} #{message}")
      mark_failed!(message)
      Result.new(chunks_embedded: 0, error: message)

    rescue => e
      message = "#{e.class}: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} Unexpected: #{message}")
      mark_failed!(message)
      raise  # re-raise so GenerateEmbeddingsJob retry_on can handle it
    end

    private

    def truncate(text)
      text.length > MAX_CHARS ? text[0, MAX_CHARS] : text
    end

    # Uses update_columns to bypass callbacks and validations — we only want to
    # update status columns, not trigger the after_save chunking chain again.
    def mark_processing!
      @document.update_columns(
        embedding_status: "processing",
        embedding_error:  nil
      )
    end

    def mark_completed!(count)
      @document.update_columns(
        embedding_status: "completed",
        embedding_error:  nil
      )
      Rails.logger.info(
        "[EmbeddingGenerationService] Document ##{@document.id} completed: #{count} chunk(s) embedded."
      )
    end

    def mark_failed!(message)
      @document.update_columns(
        embedding_status: "failed",
        embedding_error:  message.to_s.truncate(500)
      )
    end
  end
end
