# frozen_string_literal: true

require "net/http"
require "json"

module Ai
  class OllamaEmbeddingService
    MODEL    = "nomic-embed-text"
    BASE_URL = "http://localhost:11434"

    def initialize(text)
      @text = text
    end

    def call
      trace      = build_trace
      started_at = Time.current

      uri      = URI("#{BASE_URL}/api/embeddings")
      body     = { model: MODEL, prompt: @text }.to_json
      response = Net::HTTP.post(uri, body, "Content-Type" => "application/json")
      data     = JSON.parse(response.body)
      result   = data["embedding"]

      estimated_tokens = (@text.length / 4.0).ceil

      Langfuse.generation(
        trace_id:  trace.id,
        name:      "ollama/embed",
        model:     MODEL,
        input:     @text,
        output:    "#{result&.size || 0}d vector",
        end_time:  Time.now.utc,
        usage:     Langfuse::Models::Usage.new(
          input:       estimated_tokens,
          output:      0,
          total:       estimated_tokens,
          unit:        "TOKENS",
          input_cost:  0.0,
          output_cost: 0.0,
          total_cost:  0.0
        ),
        metadata:  { latency_ms: elapsed_ms(started_at) }
      )

      result
    rescue => e
      log_error(trace, "ollama/embed", e)
      raise
    ensure
      Langfuse.flush
    end

    private

    def build_trace
      Langfuse.trace(
        name:       "ollama_embedding",
        user_id:    Ai::LangfuseContext.user_id,
        session_id: Ai::LangfuseContext.session_id,
        metadata:   { shop: Ai::LangfuseContext.shop }.compact
      )
    end

    def log_error(trace, name, error)
      return unless trace
      Langfuse.generation(
        trace_id:       trace.id,
        name:           name,
        model:          MODEL,
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
  end
end
