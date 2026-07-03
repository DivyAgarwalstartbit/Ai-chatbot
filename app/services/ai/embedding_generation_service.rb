# frozen_string_literal: true

module Ai
  class EmbeddingGenerationService
    BATCH_SIZE = 50
    MAX_CHARS  = 30_000

    Result = Struct.new(:chunks_embedded, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def initialize(document)
      @document = document
    end

    def call
      trace      = build_trace
      started_at = Time.current

      chunks = @document.document_chunks.order(:chunk_index).to_a

      if chunks.empty?
        Rails.logger.info(
          "[EmbeddingGenerationService] Document ##{@document.id} has no chunks — skipping."
        )
        mark_completed!(0)
        return Result.new(chunks_embedded: 0, error: nil)
      end

      mark_processing!

      service       = Ai::EmbeddingService.new
      embedded_count = 0

      chunks.each_slice(BATCH_SIZE) do |batch|
        texts   = batch.map { |c| truncate(c.content) }
        vectors = service.embed_batch(texts)

        now = Time.current

        existing_ids = DocumentChunk.where(id: batch.map(&:id)).pluck(:id).to_set

        rows = batch.zip(vectors).filter_map do |chunk, vector|
          next unless existing_ids.include?(chunk.id)
          { id: chunk.id, embedding: vector, embedded_at: now }
        end

        next if rows.empty?

        rows.each do |row|
          DocumentChunk
            .where(id: row[:id])
            .update_all(
              embedding:   row[:embedding],
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

      Langfuse.span(
        trace_id: trace.id,
        name:     "embedding_generation/document",
        input:    { document_id: @document.id, total_chunks: chunks.size },
        output:   { chunks_embedded: embedded_count },
        end_time: Time.now.utc,
        metadata: { latency_ms: elapsed_ms(started_at), provider: Ai::EmbeddingService.provider_name }
      )

      Result.new(chunks_embedded: embedded_count, error: nil)

    rescue Ai::EmbeddingService::RateLimitError => e
      message = "Rate limit reached: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} #{message}")
      mark_failed!(message)
      log_error(trace, "embedding_generation/document", e)
      Result.new(chunks_embedded: 0, error: message)

    rescue Ai::EmbeddingService::AuthenticationError => e
      message = "Authentication failed: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} #{message}")
      mark_failed!(message)
      log_error(trace, "embedding_generation/document", e)
      Result.new(chunks_embedded: 0, error: message)

    rescue Ai::EmbeddingService::ApiError => e
      message = "API error: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} #{message}")
      mark_failed!(message)
      log_error(trace, "embedding_generation/document", e)
      Result.new(chunks_embedded: 0, error: message)

    rescue => e
      message = "#{e.class}: #{e.message}"
      Rails.logger.error("[EmbeddingGenerationService] ##{@document.id} Unexpected: #{message}")
      mark_failed!(message)
      log_error(trace, "embedding_generation/document", e)
      raise
    ensure
      Langfuse.flush
    end

    private

    def build_trace
      Langfuse.trace(
        name:       "embedding_generation",
        user_id:    Ai::LangfuseContext.user_id,
        session_id: Ai::LangfuseContext.session_id,
        metadata:   { shop: Ai::LangfuseContext.shop, document_id: @document.id }.compact
      )
    end

    def log_error(trace, name, error)
      return unless trace
      Langfuse.span(
        trace_id:       trace.id,
        name:           name,
        end_time:       Time.now.utc,
        level:          "ERROR",
        status_message: error.message
      )
    rescue StandardError
      nil
    end

    def elapsed_ms(started_at)
      ((Time.current - started_at) * 1000).round
    end

    def truncate(text)
      text.length > MAX_CHARS ? text[0, MAX_CHARS] : text
    end

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
