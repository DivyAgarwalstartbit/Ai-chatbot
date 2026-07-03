# frozen_string_literal: true

module Ai
  # Generates embeddings via the OpenAI Embeddings API.
  #
  # Uses text-embedding-3-small with dimensions reduced to 768 so the vectors
  # Uses text-embedding-3-small with dimensions reduced to 768.
  #
  # Requires OPENAI_API_KEY (or Rails credentials openai_api_key).
  #
  class OpenAiEmbeddingService
    MODEL      = "text-embedding-3-small"
    DIMENSIONS = 768

    # $0.020 per 1M input tokens, no output cost
    INPUT_PRICE_PER_MILLION = 0.020

    class ApiError < StandardError; end
    class RateLimitError < ApiError; end
    class AuthenticationError < ApiError; end

    def initialize(client: nil)
      @client = client || build_client
    end

    def embed(text)
      embed_batch([text]).first
    end

    def embed_batch(texts)
      raise ArgumentError, "texts must be a non-empty array" if texts.blank?

      trace      = build_trace
      started_at = Time.current

      response = @client.embeddings(
        parameters: {
          model:      MODEL,
          input:      texts,
          dimensions: DIMENSIONS
        }
      )

      handle_error!(response)

      result = response.dig("data")
                       .sort_by { |item| item["index"] }
                       .map { |item| item["embedding"] }

      usage        = response["usage"] || {}
      input_tokens = usage["prompt_tokens"].to_i
      total_tokens = usage["total_tokens"].to_i
      cost         = (input_tokens / 1_000_000.0) * INPUT_PRICE_PER_MILLION

      Langfuse.generation(
        trace_id:  trace.id,
        name:      "openai/embed_batch",
        model:     MODEL,
        input:     texts,
        output:    "#{result.size} vectors (#{DIMENSIONS}d)",
        end_time:  Time.now.utc,
        usage:     Langfuse::Models::Usage.new(
          input:       input_tokens,
          output:      0,
          total:       total_tokens,
          unit:        "TOKENS",
          input_cost:  cost,
          output_cost: 0.0,
          total_cost:  cost
        ),
        metadata:  { latency_ms: elapsed_ms(started_at), count: texts.size }
      )

      result
    rescue OpenAI::Error => e
      log_error(trace, "openai/embed_batch", e)
      raise_typed_error(e)
    rescue => e
      log_error(trace, "openai/embed_batch", e)
      raise
    ensure
      Langfuse.flush
    end

    private

    def build_trace
      Langfuse.trace(
        name:       "openai_embedding",
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

    def build_client
      api_key = Rails.application.credentials.openai_api_key || ENV["OPENAI_API_KEY"]

      if api_key.blank?
        raise AuthenticationError,
              "OPENAI_API_KEY is not set. Add it to .env or Rails credentials."
      end

      OpenAI::Client.new(
        access_token: api_key,
        log_errors:   Rails.env.development?
      )
    end

    def handle_error!(response)
      error = response.dig("error")
      return unless error

      message = error["message"] || "OpenAI API error"
      code    = error["code"]    || error["type"]

      case code
      when "rate_limit_exceeded"
        raise RateLimitError, message
      when "invalid_api_key", "invalid_organization"
        raise AuthenticationError, message
      else
        raise ApiError, "#{code}: #{message}"
      end
    end

    def raise_typed_error(err)
      case err.message
      when /rate.?limit/i            then raise RateLimitError, err.message
      when /api.?key|unauthorized/i  then raise AuthenticationError, err.message
      else raise ApiError, err.message
      end
    end
  end
end
