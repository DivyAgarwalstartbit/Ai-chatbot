# frozen_string_literal: true

module Ai
  # Generates embeddings using nomic-embed-text via a local Ollama server.
  #
  # Requires Ollama to be running and the model pulled:
  #   ollama pull nomic-embed-text
  #
  # The Ollama API endpoint is configured via OLLAMA_URL (default: http://localhost:11434).
  #
  # Implements the same interface as OpenAiEmbeddingService so EmbeddingService
  # can delegate to either without knowing which is active.
  #
  class NomicEmbeddingService
    MODEL      = "nomic-embed-text"
    DIMENSIONS = 768

    class ApiError < StandardError; end
    class RateLimitError < ApiError; end
    class AuthenticationError < ApiError; end

    def initialize
      @base_url = ENV.fetch("OLLAMA_URL", "http://localhost:11434")
    end

    # Returns a single embedding vector (Array of 768 floats).
    def embed(text)
      embed_batch([ text ]).first
    end

    # Returns an Array of embedding vectors for the given texts.
    # Ollama's /api/embed endpoint accepts a list of inputs in one request.
    def embed_batch(texts)
      raise ArgumentError, "texts must be a non-empty array" if texts.blank?

      uri  = URI("#{@base_url}/api/embed")
      body = { model: MODEL, input: texts }.to_json

      response = make_request(uri, body)
      parse_response!(response)
    end

    private

    def make_request(uri, body)
      http          = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl  = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 60   # embedding large batches can be slow on CPU

      request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      request.body = body

      http.request(request)
    rescue Errno::ECONNREFUSED, Net::OpenTimeout => e
      raise ApiError, "Cannot connect to Ollama at #{@base_url} — is it running? (#{e.message})"
    rescue Net::ReadTimeout => e
      raise ApiError, "Ollama request timed out: #{e.message}"
    end

    def parse_response!(response)
      unless response.is_a?(Net::HTTPSuccess)
        raise ApiError, "Ollama returned HTTP #{response.code}: #{response.body.truncate(200)}"
      end

      data = JSON.parse(response.body)

      # Ollama /api/embed returns { "embeddings": [[...], [...]] }
      embeddings = data["embeddings"]
      raise ApiError, "Ollama response missing 'embeddings' key: #{response.body.truncate(200)}" if embeddings.nil?

      embeddings
    rescue JSON::ParserError => e
      raise ApiError, "Ollama returned invalid JSON: #{e.message}"
    end
  end
end
