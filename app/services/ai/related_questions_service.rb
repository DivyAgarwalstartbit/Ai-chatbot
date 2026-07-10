# frozen_string_literal: true

module Ai
  class RelatedQuestionsService
    def initialize(user_message:, bot_response:, count: 3, shop: nil)
      @user_message = user_message
      @bot_response = bot_response
      @count        = [count.to_i, 1].max.clamp(1, 5)
      @shop         = shop
    end

    def call
      messages = [
        { role: "system", content: system_prompt },
        { role: "user",   content: user_prompt }
      ]

      raw      = Ai::GroqService.new(messages, name: "related_questions").call.to_s.strip
      json_str = raw[/\[.*\]/m] || raw
      result   = JSON.parse(json_str)
      result.map(&:to_s).reject(&:blank?).first(@count)
    rescue => e
      Rails.logger.error("[RelatedQuestions] #{e.class}: #{e.message}")
      []
    end

    private

    def system_prompt
      store_ctx = Ai::StoreContext.for(@shop)

      base = <<~TEXT
        You generate short follow-up question chips for a customer support chat.

        STRICT Rules:
        - Every question MUST be a natural follow-up to BOTH the customer's exact query AND the bot's exact reply.
        - If the bot replied about shipping, all questions must be about shipping specifics.
        - If the bot replied about a product, all questions must be about that product.
        - NEVER generate a question that could appear in any random e-commerce chat — it must only make sense given this specific exchange.
        - NEVER repeat topics already covered in the bot's reply.
        - Each question: 2–6 words, chip-style label, no punctuation at the end.
        - Return ONLY a valid JSON array of strings — no markdown, no explanation, no extra keys.
      TEXT

      base += "\nStore context:\n#{store_ctx}" if store_ctx.present?
      base
    end

    def user_prompt
      <<~TEXT
        Customer asked: "#{@user_message}"
        Bot replied: "#{@bot_response.to_s.truncate(500)}"

        Generate exactly #{@count} follow-up question chips directly about the above exchange.
        Return ONLY a JSON array, e.g. ["Return window","Exchange process","Refund timeline"]
      TEXT
    end
  end
end
