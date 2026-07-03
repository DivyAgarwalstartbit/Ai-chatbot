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

    def embed(text)
      embed_batch([ text ]).first
    end

    def embed_batch(texts)
      raise ArgumentError, "texts must be a non-empty array" if texts.blank?

      trace      = build_trace
      started_at = Time.current

      uri      = URI("#{@base_url}/api/embed")
      body     = { model: MODEL, input: texts }.to_json
      response = make_request(uri, body)
      result   = parse_response!(response)

      estimated_tokens = texts.sum { |t| (t.length / 4.0).ceil }

      Langfuse.generation(
        trace_id:  trace.id,
        name:      "nomic/embed_batch",
        model:     MODEL,
        input:     texts,
        output:    "#{result.size} vectors (#{DIMENSIONS}d)",
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
        metadata:  { latency_ms: elapsed_ms(started_at), count: texts.size }
      )

      result
    rescue => e
      log_error(trace, "nomic/embed_batch", e)
      raise
    ensure
      Langfuse.flush
    end

    private

    def build_trace
      Langfuse.trace(
        name:       "nomic_embedding",
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

    def make_request(uri, body)
      http              = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 60

      request      = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
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

      data       = JSON.parse(response.body)
      embeddings = data["embeddings"]
      raise ApiError, "Ollama response missing 'embeddings' key: #{response.body.truncate(200)}" if embeddings.nil?

      embeddings
    rescue JSON::ParserError => e
      raise ApiError, "Ollama returned invalid JSON: #{e.message}"
    end
  end
end
