require "net/http"
require "json"


module Ai
class GroqService
def initialize(messages)
 @messages = messages
end



  def call
    uri = URI("https://api.groq.com/openai/v1/chat/completions")

    response = Net::HTTP.post(
      uri,
      { model: "llama-3.1-8b-instant", messages: @messages, temperature: 0.1 }.to_json,
      { "Authorization" => "Bearer #{ENV['GROQ_API_KEY']}", "Content-Type" => "application/json" }
    )

    data = JSON.parse(response.body)
    data.dig("choices", 0, "message", "content")
  end

  # Streams tokens by yielding each chunk as it arrives from Groq.
  # Returns the full accumulated text when done.
  def stream
    uri = URI("https://api.groq.com/openai/v1/chat/completions")
    full_text = ""
    line_buf  = ""

    Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{ENV['GROQ_API_KEY']}"
      req["Content-Type"]  = "application/json"
      req.body = {
        model: "llama-3.1-8b-instant", messages: @messages, temperature: 0.1, stream: true
      }.to_json

      http.request(req) do |response|
        response.read_body do |chunk|
          line_buf += chunk
          while (newline_idx = line_buf.index("\n"))
            line     = line_buf.slice!(0..newline_idx).strip
            next unless line.start_with?("data: ")

            payload = line.delete_prefix("data: ")
            next if payload == "[DONE]"

            begin
              token = JSON.parse(payload).dig("choices", 0, "delta", "content")
              if token.present?
                full_text += token
                yield token
              end
            rescue JSON::ParserError
              next
            end
          end
        end
      end
    end

    full_text
  end
end
end
