# frozen_string_literal: true

module Ai
  class RelatedQuestionsService
    def initialize(user_message:, bot_response:, count: 3)
      @user_message = user_message
      @bot_response = bot_response
      @count        = [count.to_i, 1].max.clamp(1, 5)
    end

    def call
      messages = [
        {
          role:    "system",
          content: "You generate short follow-up questions for e-commerce support conversations. " \
                   "Return ONLY a valid JSON array of strings — no markdown, no explanation."
        },
        {
          role:    "user",
          content: <<~TEXT
            Customer asked: #{@user_message}
            Support replied: #{@bot_response.to_s.truncate(400)}

            Generate exactly #{@count} short follow-up questions the customer might ask next.
            Return ONLY a JSON array, e.g. ["Question one?","Question two?","Question three?"]
          TEXT
        }
      ]

      raw = Ai::GroqService.new(messages, name: "related_questions").call.to_s.strip
      # Extract JSON array even if the model wraps it in markdown
      json_str = raw[/\[.*\]/m] || raw
      result   = JSON.parse(json_str)
      result.map(&:to_s).reject(&:blank?).first(@count)
    rescue => e
      Rails.logger.error("[RelatedQuestions] #{e.class}: #{e.message}")
      []
    end
  end
end
