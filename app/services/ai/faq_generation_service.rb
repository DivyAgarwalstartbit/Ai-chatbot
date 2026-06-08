# frozen_string_literal: true

require "faraday"
require "faraday/net_http"
require "json"

module Ai
  # Sends extracted text to Groq and parses out FAQ question/answer pairs.
  #
  # Groq runs llama-3.3-70b — fast, free tier (14,400 req/day), production-ready.
  # API is OpenAI-compatible so the request format is simple.
  #
  # Usage:
  #   result = Ai::FaqGenerationService.new(text).call
  #   result.faqs   # => [{ "question" => "...", "answer" => "..." }, ...]
  #   result.error  # => nil on success, String on failure
  #
  class FaqGenerationService
    MODEL    = "llama-3.3-70b-versatile"
    API_BASE = "https://api.groq.com"

    # Limit input to ~12 000 chars to keep latency reasonable
    MAX_INPUT_CHARS = 12_000

    Result = Struct.new(:faqs, :error, keyword_init: true) do
      def success? = error.nil?
    end

    class ApiError            < StandardError; end
    class RateLimitError      < ApiError; end
    class AuthenticationError < ApiError; end

    def initialize(text)
      @text = text.to_s.strip
    end

    def call
      return Result.new(faqs: [], error: "No text provided.") if @text.blank?

      api_key = Rails.application.credentials.groq_api_key || ENV["GROQ_API_KEY"]
      if api_key.blank?
        return Result.new(faqs: [], error: "GROQ_API_KEY is not set. Add it to .env or Rails credentials.")
      end

      input = @text.length > MAX_INPUT_CHARS ? @text[0, MAX_INPUT_CHARS] : @text
      raw   = call_groq(api_key, input)
      faqs  = parse_json(raw)

      Result.new(faqs: faqs, error: nil)

    rescue RateLimitError => e
      Rails.logger.error("[FaqGenerationService] Rate limit: #{e.message}")
      Result.new(faqs: [], error: "Groq API rate limit reached. Please try again in a moment.")

    rescue AuthenticationError => e
      Rails.logger.error("[FaqGenerationService] Auth error: #{e.message}")
      Result.new(faqs: [], error: "Groq API key is invalid. Check GROQ_API_KEY in .env. (#{e.message})")

    rescue ApiError => e
      Rails.logger.error("[FaqGenerationService] API error: #{e.message}")
      Result.new(faqs: [], error: "Groq API error: #{e.message}")

    rescue JSON::ParserError => e
      Rails.logger.error("[FaqGenerationService] JSON parse failed: #{e.message}")
      Result.new(faqs: [], error: "Could not parse the response from Groq. Please try again.")

    rescue => e
      Rails.logger.error("[FaqGenerationService] Unexpected error: #{e.class}: #{e.message}")
      Result.new(faqs: [], error: "An unexpected error occurred. Please try again.")
    end

    private

    # ---------------------------------------------------------------------------
    # HTTP — Groq uses the OpenAI-compatible chat completions API
    # ---------------------------------------------------------------------------

    def call_groq(api_key, text)
      conn = Faraday.new(url: API_BASE) do |f|
        f.request  :json
        f.response :json
        f.adapter  Faraday.default_adapter
      end

      body = {
        model:       MODEL,
        temperature: 0.3,
        max_tokens:  4096,
        messages: [
          { role: "system", content: system_prompt },
          { role: "user",   content: user_prompt(text) }
        ],
        response_format: { type: "json_object" }  # forces valid JSON output
      }

      response = conn.post(
        "/openai/v1/chat/completions",
        body,
        { "Authorization" => "Bearer #{api_key}" }
      )

      handle_http_error!(response)
      extract_text(response.body)
    end

    def handle_http_error!(response)
      return if response.status == 200

      message = response.body.dig("error", "message") || "Unknown error"

      case response.status
      when 401, 403
        raise AuthenticationError, "HTTP #{response.status}: #{message}"
      when 429
        raise RateLimitError, "HTTP 429: #{message}"
      else
        raise ApiError, "HTTP #{response.status}: #{message}"
      end
    end

    # ---------------------------------------------------------------------------
    # Response parsing
    # ---------------------------------------------------------------------------

    def extract_text(body)
      # OpenAI-compatible response:
      # { "choices" => [{ "message" => { "content" => "..." } }] }
      text = body.dig("choices", 0, "message", "content")

      if text.nil?
        finish_reason = body.dig("choices", 0, "finish_reason")
        raise ApiError, "Groq returned no content (finish_reason: #{finish_reason})"
      end

      text.strip
    end

    def parse_json(raw)
      # Strip accidental markdown code fences just in case
      cleaned = raw.gsub(/\A```(?:json)?\s*/i, "").gsub(/\s*```\z/, "").strip

      parsed = JSON.parse(cleaned)

      # response_format: json_object may wrap the array: { "faqs": [...] }
      if parsed.is_a?(Hash)
        parsed = parsed["faqs"] || parsed["questions"] || parsed.values.first
      end

      unless parsed.is_a?(Array)
        raise JSON::ParserError, "Expected JSON array, got #{parsed.class}: #{cleaned.truncate(200)}"
      end

      # Normalise: keep only items with non-blank question and answer
      parsed.filter_map do |item|
        next unless item.is_a?(Hash)
        q = (item["question"] || item["q"]).to_s.strip
        a = (item["answer"]   || item["a"]).to_s.strip
        next if q.blank? || a.blank?
        { "question" => q, "answer" => a }
      end
    end

    # ---------------------------------------------------------------------------
    # Prompts
    # ---------------------------------------------------------------------------

    def system_prompt
      <<~PROMPT.strip
        You are an expert Shopify customer support knowledge base assistant.

        Analyze the content and generate FAQ pairs.

        Do NOT simply extract existing questions.

        Instead, identify important concepts and generate realistic questions that merchants or customers would naturally ask.

        Requirements:

        * Generate between 15 and 20 FAQs.
        * Cover all major sections of the content.
        * Include setup questions.
        * Include feature questions.
        * Include troubleshooting questions when applicable.
        * Include "how does it work" questions.
        * Include configuration questions.
        * Include user-facing questions.
        * Avoid duplicates.
        * Do not invent facts not present in the content.

        Return JSON only.

        Format:

        [
        {
        "question": "...",
        "answer": "..."
        }
        ]
        Example:
        {"faqs":[{"question":"What is your return window?","answer":"We accept returns within 30 days of purchase."}]}
      PROMPT
    end

    def user_prompt(text)
      <<~PROMPT.strip
        Generate FAQ pairs from the following content:

        ---
        #{text}
        ---

        Respond with ONLY the JSON object.
      PROMPT
    end
  end
end
