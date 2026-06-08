# frozen_string_literal: true

module Ai
  # Provider-agnostic embedding facade.
  #
  # Selects the backend based on the EMBEDDING_PROVIDER env var:
  #   EMBEDDING_PROVIDER=nomic   → Ai::NomicEmbeddingService  (default, no API key needed)
  #   EMBEDDING_PROVIDER=openai  → Ai::OpenAiEmbeddingService (requires OPENAI_API_KEY)
  #
  # Both providers produce 768-dimensional vectors so embeddings are comparable
  # regardless of which provider generated them.
  #
  # Usage:
  #   vector  = Ai::EmbeddingService.new.embed("some text")
  #   vectors = Ai::EmbeddingService.new.embed_batch(["text one", "text two"])
  #
  # Error classes re-exported here so callers only need to rescue Ai::EmbeddingService::*
  # regardless of which provider is active.
  #
  class EmbeddingService
    DIMENSIONS = 768

    # Re-export provider-neutral error classes.
    class ApiError < StandardError; end
    class RateLimitError < ApiError; end
    class AuthenticationError < ApiError; end

    PROVIDERS = %w[nomic openai].freeze

    def initialize
      @provider = build_provider
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

    # Returns the active provider name as a string ("nomic" or "openai").
    def self.provider_name
      name = ENV.fetch("EMBEDDING_PROVIDER", "nomic").downcase.strip
      unless PROVIDERS.include?(name)
        raise ArgumentError,
              "Unknown EMBEDDING_PROVIDER '#{name}'. Valid values: #{PROVIDERS.join(', ')}"
      end
      name
    end

    private

    def build_provider
      case self.class.provider_name
      when "openai"
        Ai::OpenAiEmbeddingService.new
      else
        Ai::NomicEmbeddingService.new
      end
    end

    # Map provider-specific errors to the neutral hierarchy so EmbeddingJob
    # retry_on / discard_on rules work regardless of provider.
    def reraise_as_neutral(err)
      case err
      when Ai::NomicEmbeddingService::RateLimitError,
           Ai::OpenAiEmbeddingService::RateLimitError
        raise RateLimitError, err.message
      when Ai::NomicEmbeddingService::AuthenticationError,
           Ai::OpenAiEmbeddingService::AuthenticationError
        raise AuthenticationError, err.message
      when Ai::NomicEmbeddingService::ApiError,
           Ai::OpenAiEmbeddingService::ApiError
        raise ApiError, err.message
      else
        raise err
      end
    end
  end
end
