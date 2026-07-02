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
        You generate short, relevant follow-up questions for a customer support chat.

        Rules:
        - Each question must be 2–6 words max — punchy chip-style labels, not full sentences.
        - Questions must be directly related to the customer's current query and the bot's reply.
        - Questions must be realistic things this specific store's customers would ask next.
        - Do NOT generate generic e-commerce questions unrelated to the conversation.
        - Do NOT repeat what was already asked or answered.
        - Return ONLY a valid JSON array of strings — no markdown, no explanation.
      TEXT

      base += "\nStore context (use to keep questions relevant to this shop):\n#{store_ctx}" if store_ctx.present?
      base
    end

    def user_prompt
      <<~TEXT
        Customer asked: #{@user_message}
        Support replied: #{@bot_response.to_s.truncate(400)}

        Generate exactly #{@count} short follow-up questions (2–6 words each).
        Return ONLY a JSON array, e.g. ["Track my order","Return policy","Available sizes"]
      TEXT
    end
  end
end
