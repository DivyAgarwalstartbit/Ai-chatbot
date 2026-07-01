module Ai
  class GroqService
    MODEL = "llama-3.1-8b-instant".freeze

    INPUT_PRICE_PER_MILLION  = 0.05
    OUTPUT_PRICE_PER_MILLION = 0.08

    def initialize(messages, name: "groq", user_id: nil, session_id: nil)
      @messages   = messages
      @name       = name
      @user_id    = user_id    || Ai::LangfuseContext.user_id
      @session_id = session_id || Ai::LangfuseContext.session_id
    end

    # ── Blocking call ────────────────────────────────────────────────
    def call
      trace      = build_trace
      started_at = Time.current

      response = Net::HTTP.post(
        URI("https://api.groq.com/openai/v1/chat/completions"),
        { model: MODEL, messages: @messages, temperature: 0.1 }.to_json,
        "Authorization" => "Bearer #{ENV["GROQ_API_KEY"]}",
        "Content-Type"  => "application/json"
      )

      latency = elapsed_ms(started_at)
      data    = JSON.parse(response.body)
      output  = data.dig("choices", 0, "message", "content")
      usage   = data["usage"] || {}

      # Single generation-create event with all data — no update needed
      Langfuse.generation(
        trace_id:   trace.id,
        name:       "#{@name}/call",
        model:      MODEL,
        input:      @messages,
        output:     output,
        end_time:   Time.now.utc,
        usage:      build_usage(usage),
        metadata:   { latency_ms: latency }
      )

      output
    rescue => e
      log_error(trace, "#{@name}/call", e)
      raise
    ensure
      Langfuse.flush
    end

    # ── Streaming call ───────────────────────────────────────────────
    def stream
      trace      = build_trace
      started_at = Time.current

      full_text    = ""
      line_buf     = ""
      stream_usage = {}

      Net::HTTP.start("api.groq.com", 443, use_ssl: true, read_timeout: 120) do |http|
        req = Net::HTTP::Post.new("/openai/v1/chat/completions")
        req["Authorization"] = "Bearer #{ENV["GROQ_API_KEY"]}"
        req["Content-Type"]  = "application/json"
        req.body = {
          model:          MODEL,
          messages:       @messages,
          temperature:    0.1,
          stream:         true,
          stream_options: { include_usage: true }
        }.to_json

        http.request(req) do |response|
          response.read_body do |chunk|
            line_buf += chunk

            while (idx = line_buf.index("\n"))
              line = line_buf.slice!(0..idx).strip
              next unless line.start_with?("data: ")

              payload = line.delete_prefix("data: ")
              next if payload == "[DONE]"

              begin
                parsed = JSON.parse(payload)

                # Final usage-only chunk from Groq (stream_options.include_usage)
                if parsed["usage"]
                  stream_usage = parsed["usage"]
                  next
                end

                token = parsed.dig("choices", 0, "delta", "content")
                next unless token

                full_text << token
                yield token
              rescue JSON::ParserError
              end
            end
          end
        end
      end

      # Single generation-create event with all data — no update needed
      Langfuse.generation(
        trace_id:   trace.id,
        name:       "#{@name}/stream",
        model:      MODEL,
        input:      @messages,
        output:     full_text,
        end_time:   Time.now.utc,
        usage:      build_usage(stream_usage),
        metadata:   { latency_ms: elapsed_ms(started_at) }
      )

      full_text
    rescue => e
      log_error(trace, "#{@name}/stream", e)
      raise
    ensure
      Langfuse.flush
    end

    private

    def build_trace
      Langfuse.trace(
        name:       @name,
        user_id:    @user_id,
        session_id: @session_id,
        metadata:   { shop: Ai::LangfuseContext.shop }.compact
      )
    end

    def build_usage(raw)
      input_tokens  = raw["prompt_tokens"].to_i
      output_tokens = raw["completion_tokens"].to_i

      Langfuse::Models::Usage.new(
        input:       input_tokens,
        output:      output_tokens,
        total:       raw["total_tokens"].to_i,
        unit:        "TOKENS",
        input_cost:  (input_tokens  / 1_000_000.0) * INPUT_PRICE_PER_MILLION,
        output_cost: (output_tokens / 1_000_000.0) * OUTPUT_PRICE_PER_MILLION,
        total_cost:  (input_tokens  / 1_000_000.0) * INPUT_PRICE_PER_MILLION +
                     (output_tokens / 1_000_000.0) * OUTPUT_PRICE_PER_MILLION
      )
    end

    def log_error(trace, name, error)
      return unless trace
      Langfuse.generation(
        trace_id:       trace.id,
        name:           name,
        model:          MODEL,
        input:          @messages,
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
