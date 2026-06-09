# frozen_string_literal: true

module Ai
  # Generates embeddings via the OpenAI Embeddings API.
  #
  # Uses text-embedding-3-small with dimensions reduced to 768 so the vectors
  # are compatible with those produced by NomicEmbeddingService.
  #
  # Requires OPENAI_API_KEY (or Rails credentials openai_api_key).
  #
  class OpenAiEmbeddingService
    MODEL      = "text-embedding-3-small"
    DIMENSIONS = 768   # reduced from 1536 to match nomic-embed-text

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

      response = @client.embeddings(
        parameters: {
          model:      MODEL,
          input:      texts,
          dimensions: DIMENSIONS
        }
      )

      handle_error!(response)

      response.dig("data")
              .sort_by { |item| item["index"] }
              .map { |item| item["embedding"] }
    rescue OpenAI::Error => e
      raise_typed_error(e)
    end

    private

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
      when /rate.?limit/i   then raise RateLimitError, err.message
      when /api.?key|unauthorized/i then raise AuthenticationError, err.message
      else raise ApiError, err.message
      end
    end
  end
end
