module Ai
  class ChatGenerationService
    TONE_INSTRUCTIONS = {
      "friendly"     => "Be warm, friendly, and conversational. Use simple language and feel free to use light, natural expressions.",
      "professional" => "Maintain a professional, courteous tone. Be precise, helpful, and polished in every reply.",
      "formal"       => "Use formal, respectful language at all times. Avoid contractions, slang, and casual phrasing.",
      "playful"      => "Be upbeat, enthusiastic, and fun. You can use emojis occasionally and keep the energy light and positive.",
      "empathetic"   => "Lead every response with empathy and understanding. Acknowledge the customer's feelings before providing solutions.",
      "concise"      => "Be brief and direct. Prioritize clarity above all else. Cut any words that are not essential."
    }.freeze

    def initialize(message:, context: nil, instructions: nil, stream_callback: nil, shop: nil)
      @message         = message
      @context         = context
      @instructions    = instructions
      @stream_callback = stream_callback
      @shop            = shop
    end

    def call
      messages = [
        { role: "system", content: system_prompt },
        { role: "user",   content: @message }
      ]

      svc = Ai::GroqService.new(messages)

      if @stream_callback
        svc.stream { |token| @stream_callback.call(token) }
      else
        svc.call
      end
    end

    private

    def system_prompt
      store_ctx = Ai::StoreContext.for(@shop)

      <<~TEXT
        You are a customer support agent for an e-commerce store.
        #{store_ctx.present? ? "\nStore Information:\n#{store_ctx}\n" : ""}
        Tone: #{tone_instruction}

        Guidelines:
        - Reply ONLY using the information in the Context below and the Store Information above.
        - Do NOT add, assume, or invent any details not present in either.
        - If asked for the support email or phone, use the Store Information values above.
        - If the Context does not contain the answer, say you don't have that information — never make it up.
        - Keep responses short (2–3 sentences) unless more detail is genuinely needed.
        - Do not ask follow-up questions unless the Additional Instructions specifically require it.
        #{custom_instructions_block}
        Additional Instructions:
        #{@instructions}

        Context:
        #{@context}
      TEXT
    end

    def tone_instruction
      cfg  = shop_config
      tone = cfg&.brand_tone.presence || "friendly"
      TONE_INSTRUCTIONS[tone] || TONE_INSTRUCTIONS["friendly"]
    end

    def custom_instructions_block
      cfg   = shop_config
      ws    = (cfg&.widget_settings || {}).with_indifferent_access
      text  = ws[:custom_instructions].to_s.strip
      return "" if text.blank?

      "Shop-specific instructions (follow these closely):\n#{text}\n"
    end

    def shop_config
      @shop_config ||= @shop&.ai_shopper_configuration
    end
  end
end
