# frozen_string_literal: true

module Ai
  # Provider-agnostic embedding facade — delegates to OpenAiEmbeddingService.
  #
  # Requires OPENAI_API_KEY (or Rails credentials openai_api_key).
  #
  # Usage:
  #   vector  = Ai::EmbeddingService.new.embed("some text")
  #   vectors = Ai::EmbeddingService.new.embed_batch(["text one", "text two"])
  #
  class EmbeddingService
    DIMENSIONS = 768

    class ApiError < StandardError; end
    class RateLimitError < ApiError; end
    class AuthenticationError < ApiError; end

    def initialize
      @provider = Ai::OpenAiEmbeddingService.new
    end

    def embed(text)
      @provider.embed(text)
    rescue => e
      reraise_as_neutral(e)
    end

    def embed_batch(texts)
      @provider.embed_batch(texts)
    rescue => e
      reraise_as_neutral(e)
    end

    def self.provider_name
      "openai"
    end

    private

    def reraise_as_neutral(err)
      case err
      when Ai::OpenAiEmbeddingService::RateLimitError
        raise RateLimitError, err.message
      when Ai::OpenAiEmbeddingService::AuthenticationError
        raise AuthenticationError, err.message
      when Ai::OpenAiEmbeddingService::ApiError
        raise ApiError, err.message
      else
        raise err
      end
    end
  end
end
