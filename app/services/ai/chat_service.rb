module Ai
  class ChatService
    def initialize(shop:, customer:, session_id:, message:, stream_callback: nil)
      @shop            = shop
      @customer        = customer
      @session_id      = session_id
      @message         = message.to_s.strip
      @stream_callback = stream_callback
    end

    def call
      memory = Ai::MemoryService.new(
        shop:       @shop,
        customer:   @customer,
        session_id: @session_id
      )

      memory.add(role: "user", content: @message, shop: @shop)

      # ── Handoff guard ──────────────────────────────────────────
      if memory.conversation.handoff_mode?
        return {
          type:    "human_handoff_active",
          message: "You're connected with our support team. Your message has been logged and an agent will respond shortly."
        }
      end

      # ── Recommendation confirmation guard ──────────────────────
      # When the bot previously asked "want me to recommend similar?",
      # intercept the next message here before running intent detection.
      if memory.awaiting_recommendation?
        response = handle_recommendation_confirmation(memory)
        if response
          memory.add(role: "assistant", content: memory_content(response))
          return response
        end
        # nil means the user said something unrelated — fall through to
        # normal intent detection with the pending state already cleared.
      end

      # ── Intent detection ───────────────────────────────────────
      intent_context = memory.get_context.merge(
        "recent_messages" => memory.recent_messages_text
      )

      intent = Ai::IntentService.new(
        message: @message,
        context: intent_context,
        shop:    @shop
      ).call

      Rails.logger.info("INTENT => #{intent}")
      memory.set_last_intent(intent)

      # ── Route ──────────────────────────────────────────────────
      response = Ai::RouterService.new(
        shop:            @shop,
        customer:        @customer,
        message:         @message,
        intent:          intent,
        memory:          memory,
        stream_callback: @stream_callback
      ).call

      # Append related follow-up questions if the feature is enabled for this shop
      response = append_related_questions(response)

      # Store the full structured response as metadata so history can re-render cards.
      # Strip session_id — that's a transport field, not display data.
      stored_metadata = response.is_a?(Hash) ? response.except(:session_id) : nil
      memory.add(role: "assistant", content: memory_content(response), metadata: stored_metadata)

      # Always include the active session_id so the widget can sync
      # if the conversation was rotated (stale/closed → fresh one created).
      response.is_a?(Hash) ? response.merge(session_id: memory.conversation.session_id) : response
    end

    private

    # ──────────────────────────────────────────────────────────────
    # RECOMMENDATION CONFIRMATION
    # Returns a response hash, or nil (fall through to intent flow).
    # ──────────────────────────────────────────────────────────────
    def handle_recommendation_confirmation(memory)
      if user_said_yes?
        query  = memory.pending_recommendation_query
        reason = memory.pending_recommendation_reason
        memory.clear_recommendation_wait
        serve_recommendations(query, reason, memory)
      elsif user_said_no?
        memory.clear_recommendation_wait
        {
          success:  true,
          type:     "text",
          message:  "No problem! Let me know if there's anything else I can help with.",
          products: []
        }
      else
        # Ambiguous — treat as a fresh query
        memory.clear_recommendation_wait
        nil
      end
    end

    def serve_recommendations(analyzed_query, reason, memory)
      products = Ai::ProductRecommendationService.new(
        shop:           @shop,
        analyzed_query: analyzed_query
      ).call.first(3)

      if products.blank?
        return {
          success:  true,
          type:     "text",
          message:  "I'm sorry, I couldn't find similar products right now. Feel free to describe what you're looking for and I'll do my best to help.",
          products: []
        }
      end

      memory.set_active_product(products.first)

      intro = reason == "out_of_stock" ?
        "Here are some similar alternatives that are currently available:" :
        "Here are some products you might like:"

      {
        success:  true,
        type:     "product_cards",
        message:  intro,
        products: build_recommendation_cards(products)
      }
    end

    def build_recommendation_cards(products)
      products.map do |p|
        {
          id:       p.id,
          title:    p.title,
          image:    p.image_url,
          handle:   p.handle,
          variants: p.product_variants.map do |v|
            { id: v.id, title: v.title, price: v.price, stock: v.inventory_quantity }
          end
        }
      end
    end

    # ──────────────────────────────────────────────────────────────
    # YES / NO DETECTION
    # ──────────────────────────────────────────────────────────────
    def user_said_yes?
      @message.downcase.match?(/\b(yes|yeah|sure|ok|okay|please|yep|yup|go ahead|do it|show me|recommend|why not|sounds good|absolutely|of course|definitely)\b/)
    end

    def user_said_no?
      @message.downcase.match?(/\b(no|nope|nah|not really|no thanks|don't|skip|never mind|nevermind|that'?s? ok|i'?m good)\b/)
    end

    # ──────────────────────────────────────────────────────────────
    # HELPERS
    # ──────────────────────────────────────────────────────────────
    def memory_content(response)
      return response unless response.is_a?(Hash)

      titles = response[:products]&.map { |p| p[:title] }&.compact&.join(", ")
      msg    = response[:message].to_s

      titles.present? ? "#{msg} Products shown: #{titles}" : msg
    end

    # ──────────────────────────────────────────────────────────────
    # RELATED QUESTIONS
    # ──────────────────────────────────────────────────────────────
    def append_related_questions(response)
      return response unless response.is_a?(Hash)
      return response unless related_questions_enabled?

      bot_text = response[:message].to_s
      return response if bot_text.blank?

      count     = related_questions_count
      questions = Ai::RelatedQuestionsService.new(
        user_message: @message,
        bot_response:  bot_text,
        count:         count,
        shop:          @shop
      ).call

      questions.any? ? response.merge(related_questions: questions) : response
    end

    def related_questions_enabled?
      ws = shop_widget_settings
      ws[:enable_related_questions].nil? ? true : ws[:enable_related_questions].to_s == "true"
    end

    def related_questions_count
      ws = shop_widget_settings
      ws[:related_questions_count].to_i.nonzero? || 3
    end

    def shop_widget_settings
      @shop_widget_settings ||= begin
        cfg = @shop&.ai_shopper_configuration
        (cfg&.widget_settings || {}).with_indifferent_access
      end
    end
  end
end
