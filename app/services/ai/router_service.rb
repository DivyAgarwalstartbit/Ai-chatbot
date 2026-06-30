module Ai
  class RouterService
    def initialize(shop:, customer: nil, message:, intent: {}, memory: nil, stream_callback: nil)
      @shop            = shop
      @customer        = customer
      @message         = message.to_s.strip
      @intent          = normalize_intent(intent)
      @memory          = memory
      @stream_callback = stream_callback
    end

    # Intents allowed without a Shopify account
    GUEST_ALLOWED_INTENTS = %w[
      greeting
      product_search
      product_detail
      product_comparison
      product_recommendation
      faq
      shipping_policy
      return_policy
      additional_docs
      general
    ].freeze

    # ==================================================
    # ENTRY
    # ==================================================
    def call
      # Block guests from restricted intents before anything else
      return auth_required_response if guest_blocked?

      # Auto-escalate if conversation is active for an order issue
      return auto_escalate_order_issue if should_auto_escalate_order?

      # If the user has an active order in memory and this looks like a follow-up
      # about it, route straight to order_agent so the LLM answers from cache
      # rather than showing the lookup form again.
      return order_agent if order_context_followup?

      route_primary(@intent[:primary_intent])
    end

    private

    # ==================================================
    # NORMALIZE
    # ==================================================
    def normalize_intent(intent)
      return { primary_intent: "general", secondary_intents: [], uses_previous_context: false } if intent.blank?

      {
        primary_intent:       intent[:primary_intent].to_s.downcase,
        secondary_intents:    Array(intent[:secondary_intents]).map(&:to_s).map(&:downcase),
        uses_previous_context: intent[:uses_previous_context] == true
      }
    end

    # ==================================================
    # PRIMARY ROUTING
    # ==================================================
    def route_primary(primary)
      case primary
      when "product_search", "product_detail"
        product_agent

      when "product_recommendation"
        recommendation_agent

      when "product_comparison"
        product_agent   # comparison is handled inside ProductAgentService

      when "order_status"
        order_agent

      when "human_escalation"
        human_escalation_agent

      when "greeting"
        {
          type:    "text",
          message: "Hi 👋 How can I help you today? I can help you find products, check your order, or answer questions."
        }

      when "faq", "shipping_policy", "return_policy", "additional_docs"
        knowledge_agent

      when "order_issue"
        human_escalation_agent

      else
        safe_general_response
      end
    end

    # ==================================================
    # ORDER CONTEXT FOLLOWUP
    # Routes to order_agent when an active order is in memory and the message
    # is plausibly about that order — covers cases where IntentService returns
    # "general" instead of "order_status" for follow-up questions.
    # ==================================================
    ORDER_FOLLOWUP_KEYWORDS = %w[
      track tracking delivery deliver arrive arrived received
      ship shipped shipping dispatch status order package
      where when estimated eta refund return exchange cancel
    ].freeze

    def order_context_followup?
      return false unless @memory.respond_to?(:active_order) && @memory.active_order.present?

      # These intents clearly aren't about the cached order — let them route normally
      non_order_intents = %w[product_search product_detail product_recommendation product_comparison greeting human_escalation]
      return false if non_order_intents.include?(@intent[:primary_intent])

      # Explicit order intent always qualifies
      return true if @intent[:primary_intent] == "order_status"

      # For ambiguous intents (general, faq, etc.) check for order-related keywords
      msg = @message.downcase
      ORDER_FOLLOWUP_KEYWORDS.any? { |kw| msg.include?(kw) }
    end

    # ==================================================
    # AUTO-ESCALATION FOR ORDER ISSUES
    # ==================================================
    def should_auto_escalate_order?
      return false unless @memory.respond_to?(:active_order)
      return false unless @memory.active_order.present?
      return false if @intent[:primary_intent] == "human_escalation"

      ORDER_ESCALATION_KEYWORDS.any? { |kw| @message.downcase.include?(kw) }
    end

    ORDER_ESCALATION_KEYWORDS = %w[
      return refund exchange cancel payment dispute
      damaged wrong missing broken defective
    ].freeze

    def auto_escalate_order_issue
      Ai::HumanEscalationService.new(
        shop:     @shop,
        customer: @customer,
        message:  @message,
        memory:   @memory
      ).call.merge(
        message: "I see you have an issue with your order. I've raised a support ticket and a human agent will assist you shortly."
      )
    end

    # ==================================================
    # AGENTS
    # ==================================================
    def product_agent
      Ai::ProductAgentService.new(
        shop:            @shop,
        message:         @message,
        intent:          @intent,
        memory:          @memory,
        stream_callback: @stream_callback
      ).call
    end

    def recommendation_agent
      Ai::ProductRecommendationAgentService.new(
        shop:            @shop,
        message:         @message,
        intent:          @intent,
        memory:          @memory,
        stream_callback: @stream_callback
      ).call
    end

    def order_agent
      Ai::OrderAgentService.new(
        shop:     @shop,
        customer: @customer,
        message:  @message,
        memory:   @memory
      ).call
    end

    def knowledge_agent
      Ai::KnowledgeAgentService.new(
        shop:            @shop,
        message:         @message,
        memory:          @memory,
        stream_callback: @stream_callback
      ).call
    end

    def human_escalation_agent
      Ai::HumanEscalationService.new(
        shop:     @shop,
        customer: @customer,
        message:  @message,
        memory:   @memory
      ).call
    end

    # ==================================================
    # GUEST AUTH GATE
    # ==================================================
    def guest_blocked?
      return false unless @customer.respond_to?(:guest?) && @customer.guest?

      !GUEST_ALLOWED_INTENTS.include?(@intent[:primary_intent])
    end

    def auth_required_response
      {
        type:    "auth_required",
        message: "You need to be signed in to access that. Please sign in or create an account to continue."
      }
    end

    # ==================================================
    # SAFE FALLBACK
    # ==================================================
    def safe_general_response
      answer = Ai::ChatGenerationService.new(
        message:         @message,
        context:         @memory.respond_to?(:context) ? @memory.context : "",
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    <<~TEXT
          You are a friendly e-commerce support assistant.
          - Answer only what you know.
          - If the user seems to be looking for a product, say you can help them search.
          - Keep responses short (2-3 sentences).
        TEXT
      ).call

      { type: "text", message: answer }
    end
  end
end
