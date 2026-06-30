module Ai
  class IntentService
    VALID_INTENTS = %w[
      product_search
      product_detail
      product_recommendation
      product_comparison
      order_status
      order_issue
      shipping_policy
      return_policy
      faq
      additional_docs
      human_escalation
      greeting
      general
    ].freeze

    PRODUCT_INTENTS = %w[
      product_search
      product_detail
      product_recommendation
      product_comparison
    ].freeze

    ORDER_INTENTS  = %w[order_status order_issue].freeze
    POLICY_INTENTS = %w[shipping_policy return_policy].freeze

    def initialize(message:, context: {}, shop: nil)
      @message = message.to_s.strip
      @context = context.is_a?(Hash) ? context : {}
      @text    = @message.downcase
      @shop    = shop
    end

    def call
      return greeting_response         if greeting?
      return human_escalation_response if human_escalation?

      rule_result = rule_based_intent
      return rule_result if rule_result

      llm_fallback
    rescue => e
      Rails.logger.error("IntentService Error: #{e.class} #{e.message}")
      fallback_response
    end

    # ==================================================
    # RULE ENGINE  (order matters — most specific first)
    # ==================================================
    def rule_based_intent
      # Order follow-up must fire before product checks so "arrived?" after an
      # order doesn't leak into product_detail.
      return order_followup_intent   if order_followup?
      return product_detail_intent   if product_detail?
      return product_intent          if product_intent?
      return order_intent            if order_intent?
      return policy_intent           if policy_intent?
      return faq_intent              if faq_intent?
      return context_continuation    if continuation?
      nil
    end

    # ==================================================
    # GREETING / ESCALATION
    # ==================================================
    def greeting?
      @text.match?(/\A(hi+|hello+|hey+|good\s+(morning|evening|afternoon|day)|howdy|greetings|sup|what'?s\s+up)[\s!?.]*\z/i) ||
        @text.match?(/\A(hi+|hello+|hey+)\b[^?]{0,25}\z/i)
    end

    def human_escalation?
      @text.match?(/\b(talk\s+to\s+(a\s+|an\s+)?(human|person|agent|representative)|speak\s+(with|to)\s+(a\s+|an\s+)?(human|agent|person)|connect\s+(me\s+)?(with|to)\s+(a\s+|an\s+)?(human|agent)|live\s+agent|real\s+(agent|person|human)|customer\s+service|escalate|file\s+a\s+complaint|raise\s+a\s+complaint|need\s+(help\s+from\s+someone|a\s+human|an\s+agent))\b/i)
    end

    def greeting_response
      { primary_intent: "greeting", secondary_intents: [], uses_previous_context: false }
    end

    def human_escalation_response
      { primary_intent: "human_escalation", secondary_intents: [], uses_previous_context: false }
    end

    # ==================================================
    # ORDER FOLLOW-UP
    # Fires when the last intent was order-related AND the message is a
    # contextual follow-up (tracking, delivery, ETA, status update, etc.).
    # Classified as order_status with uses_previous_context: true so the
    # router can answer from the active order in memory without re-showing
    # the lookup form.
    # ==================================================
    def order_followup?
      return false unless ORDER_INTENTS.include?(last_intent_primary)

      @text.match?(/\b(
        track(ing)?|trace|
        when\s+will\s+(it|my|i)|
        when\s+will\s+i\s+(get|receive)|
        where\s+(is\s+)?(it|my)|where'?s|
        arrive|arrival|arrived|
        deliver(ed|y)?|
        ship(ped|ping)?|dispatch(ed)?|
        estimated|expected|eta|
        on\s+its\s+way|out\s+for\s+delivery|
        status|update|progress|
        package|parcel|
        still|yet|any\s+(update|news)|
        received?|got\s+it|
        how\s+long\s+(will|does|is)|
        what\s+(happened|about|next|now)
      )\b/x)
    end

    def order_followup_intent
      # Distinguish complaint/issue signals even in follow-up context
      if @text.match?(/\b(damage[d]?|broken|wrong|missing|lost|never\s+(arrived|received|came)|not\s+(arrived|delivered|received)|complaint|issue|problem)\b/)
        { primary_intent: "order_issue",  secondary_intents: [], uses_previous_context: true }
      else
        { primary_intent: "order_status", secondary_intents: [], uses_previous_context: true }
      end
    end

    # ==================================================
    # PRODUCT DETAIL — follow-up about a product in context
    # ==================================================
    def product_detail?
      return false unless PRODUCT_INTENTS.include?(last_intent_primary)

      @text.match?(/\b(
        spec(ification)?s?|feature|dimension|weight|material|
        size|colou?r|variant|sku|
        stock|available|in\s+stock|out\s+of\s+stock|
        how\s+much(\s+is\s+it)?|
        what'?s?\s+the\s+(price|cost)|price\s+of|cost\s+of|
        more\s+(detail|info|about)|
        tell\s+me\s+more|show\s+me\s+more|
        is\s+it\s+available|
        what\s+does\s+it\s+(come\s+in|look\s+like|include)|
        what\s+(size|color|colour|material)|
        does\s+it\s+come\s+in|
        can\s+i\s+get\s+it\s+in|
        what'?s?\s+included|
        how\s+(big|small|heavy|long|wide|tall)
      )\b/x)
    end

    def product_detail_intent
      { primary_intent: "product_detail", secondary_intents: [], uses_previous_context: true }
    end

    # ==================================================
    # PRODUCT SEARCH / RECOMMENDATION / COMPARISON
    # ==================================================
    def product_intent?
      comparison? || recommendation? || product_search_signal?
    end

    def product_intent
      return comparison     if comparison?
      return recommendation if recommendation?
      search
    end

    def comparison?
      @text.match?(/\b(vs\.?|versus|compare|comparison|difference\s+between|which\s+is\s+(better|best)|which\s+one\s+(is|should|would)|better\s+(option|choice|pick))\b/)
    end

    def recommendation?
      @text.match?(/\b(recommend|suggest|best\s+(option|for|pick|choice)|what\s+should\s+i\s+(buy|get|pick|choose)|suggest\s+me|help\s+me\s+(choose|pick|find|select)|looking\s+for\s+something|what\s+(would|do)\s+you\s+recommend|any\s+suggestion)\b/)
    end

    def product_search_signal?
      # Explicit shopping actions — always fire
      return true if @text.match?(/\b(show\s+me|find\s+me|search\s+for|looking\s+for|do\s+you\s+(have|sell|carry)|i\s+(want|need|am\s+looking\s+for)|what\s+products?\s+(do\s+you|you)\s+(have|carry|sell)|any\s+(good|decent|cheap|affordable)\s+\w+)\b/)

      # Bail if policy/order signals are also present — they take priority
      return false if policy_intent? || order_intent?

      # Core product vocabulary without a competing context
      return true if @text.match?(/\b(product|item|model|collection|variant|sku|catalogue|catalog)\b/)

      # Price inquiry with no order context
      return true if @text.match?(/\b(how\s+much\s+(is|does|for)|what'?s?\s+the\s+price|price\s+of|cost\s+of)\b/) && !order_intent?

      false
    end

    def search
      { primary_intent: "product_search", secondary_intents: [], uses_previous_context: false }
    end

    def recommendation
      { primary_intent: "product_recommendation", secondary_intents: [], uses_previous_context: false }
    end

    def comparison
      { primary_intent: "product_comparison", secondary_intents: [], uses_previous_context: false }
    end

    # ==================================================
    # ORDER INTENT — fresh order query (no prior order context)
    # ==================================================
    def order_intent?
      @text.match?(/\b(
        my\s+order|order\s+#?\d+|order\s+(number|id)|invoice|
        shipment|tracking(\s+number)?|track\s+my|
        dispatch(ed)?|
        delivery\s+(status|update|problem|issue|date|time)|
        where\s+is\s+my\s+(order|package|parcel)|
        when\s+will\s+my\s+(order|package)\s+(arrive|come|be\s+delivered|be\s+shipped)|
        when\s+will\s+i\s+(get|receive)\s+my\s+(order|package)|
        estimated\s+(arrival|delivery)|expected\s+(delivery|arrival|date)|
        has\s+(my\s+)?(order|package)\s+(shipped|been\s+shipped|left|dispatched)|
        is\s+my\s+(order|package)\s+(shipped|dispatched|out\s+for\s+delivery|delivered)|
        status\s+of\s+my\s+(order|package)|
        any\s+(update|news)\s+on\s+my\s+(order|package|shipment)|
        i\s+(haven'?t|have\s+not)\s+(received|got)\s+my\s+order
      )\b/x)
    end

    def order_intent
      uses_ctx = ORDER_INTENTS.include?(last_intent_primary)

      if @text.match?(/\b(damaged?|broken|wrong|missing|lost|complaint|issue|problem|never\s+(arrived|received|came)|not\s+(arrived|delivered|received))\b/)
        { primary_intent: "order_issue",  secondary_intents: [], uses_previous_context: uses_ctx }
      else
        { primary_intent: "order_status", secondary_intents: [], uses_previous_context: uses_ctx }
      end
    end

    # ==================================================
    # POLICY INTENT
    # ==================================================
    def policy_intent?
      @text.match?(/\b(return\s+policy|refund\s+policy|exchange\s+policy|shipping\s+policy|shipping\s+(time|cost|fee|rate)|delivery\s+(time|window|cost)|how\s+long\s+(does|will)\s+(shipping|delivery)|how\s+long\s+(to|for)\s+(deliver|arrive|ship)|warranty|guarantee|(can\s+i|how\s+(do\s+i|to))\s+(return|exchange|get\s+a\s+refund))\b/)
    end

    def policy_intent
      if @text.match?(/\b(return|exchange|refund|warranty|guarantee)\b/)
        { primary_intent: "return_policy",   secondary_intents: [], uses_previous_context: false }
      else
        { primary_intent: "shipping_policy", secondary_intents: [], uses_previous_context: false }
      end
    end

    # ==================================================
    # FAQ — store info, payments, contact, promotions
    # ==================================================
    def faq_intent?
      @text.match?(/\b(payment\s+(method|option|modes?)|do\s+you\s+accept\s+(credit|debit|paypal|apple\s+pay|google\s+pay|cash)|accept\s+(credit|debit|paypal|stripe|cash)|store\s+(hour|location|address|info)|contact\s+(us|you|support|number|email)|phone\s+number|email\s+address|where\s+are\s+you\s+located|gift\s+(card|wrap)|loyalty\s+(program|point)|reward\s+point|promo(tion)?|discount\s+code|coupon|gift\s+card\s+balance|about\s+(the\s+)?store|who\s+are\s+you|do\s+you\s+have\s+a\s+(physical|store))\b/)
    end

    def faq_intent
      { primary_intent: "faq", secondary_intents: [], uses_previous_context: false }
    end

    # ==================================================
    # CONTEXT CONTINUATION
    # Short follow-ups that clearly belong to the active topic.
    # ==================================================
    def continuation?
      last = last_intent_primary
      return false unless last.present? && short_followup?

      if PRODUCT_INTENTS.include?(last)
        return @text.match?(/\b(it|this|that|these|those|the\s+(same|one|product)|more\s+(detail|info|about)|show\s+more|tell\s+me\s+more|price|cost|how\s+much|spec|feature|dimension|weight|color|size|stock|available|in\s+stock|variant|option|another|different|other|else)\b/)
      end

      if ORDER_INTENTS.include?(last)
        # Broader match — short follow-ups after an order query are almost always about that order
        return @text.match?(/\b(
          what\s+(about|happened|next|now)|then\s+what|
          when|update|status|any\s+news|still|yet|progress|resolved|fix|
          tracking|track|trace|
          arrive|arrival|estimated|expected|eta|
          deliver(y|ed)?|ship(ped|ping)?|dispatch(ed)?|
          package|parcel|
          where('?s|\s+is)|
          receive[d]?|got\s+it|
          how\s+long|on\s+its\s+way|out\s+for\s+delivery|
          refund|return|exchange|cancel
        )\b/x)
      end

      if POLICY_INTENTS.include?(last)
        return @text.match?(/\b(what\s+about|and|also|how\s+about|okay|so|then|but|wait|one\s+more|anything\s+else)\b/)
      end

      false
    end

    def context_continuation
      {
        primary_intent:        last_intent_primary,
        secondary_intents:     [],
        uses_previous_context: true
      }
    end

    def last_intent_primary
      raw = @context["last_intent_json"]
      return nil if raw.blank?

      parsed = JSON.parse(raw) rescue nil
      parsed&.dig("primary_intent")
    end

    def short_followup?
      @message.split.length <= 10
    end

    # ==================================================
    # LLM FALLBACK — used only when no rule fires
    # ==================================================
    def llm_fallback
      messages = [ { role: "system", content: system_prompt } ]

      if @context["recent_messages"].present?
        messages << { role: "system", content: "Recent conversation:\n#{@context["recent_messages"]}" }
      end

      if @context["last_intent_json"].present?
        parsed  = JSON.parse(@context["last_intent_json"]) rescue nil
        last_pi = parsed&.dig("primary_intent")
        messages << { role: "system", content: "Last classified intent: #{last_pi}" } if last_pi
      end

      messages << { role: "user", content: @message }

      response = Ai::GroqService.new(messages).call
      normalize_response(response)
    end

    def system_prompt
      store_ctx = Ai::StoreContext.for(@shop)

      <<~PROMPT
        You are a customer-support intent classifier for an e-commerce store.
        #{store_ctx.present? ? "\nStore context (use to resolve ambiguous queries):\n#{store_ctx}\n" : ""}
        Classify the user message into exactly ONE of these intents:

          product_search         — browsing or looking for a product by name, type, or attribute
          product_detail         — asking for specs, price, stock, or details of a product already discussed
          product_recommendation — wants suggestions (recommend, best, what should I get)
          product_comparison     — wants to compare two or more products
          order_status           — asking about the location, tracking, or delivery status of an order
          order_issue            — has a problem with an order (damaged, wrong item, missing, not arrived)
          shipping_policy        — asks about shipping times or costs in general
          return_policy          — asks about returns, exchanges, refunds, or warranties in general
          faq                    — store info: payment methods, contact details, hours, discount codes
          additional_docs        — asks about a specific uploaded document or resource
          human_escalation       — wants to talk to a human / live agent
          greeting               — just saying hello with no question
          general                — anything that does not fit any category above

        Key rules:
        - If the user is clearly asking about the STATUS or LOCATION of their order, use order_status.
        - If the conversation was about an order and this message is a follow-up about it, use order_status
          with uses_previous_context: true.
        - If the user mentions a complaint about a received order (damaged, wrong, missing), use order_issue.
        - Only use general when truly nothing else fits.

        Respond with ONLY valid JSON — no markdown, no explanation:
        {
          "primary_intent": "<intent>",
          "secondary_intents": [],
          "uses_previous_context": <true|false>
        }

        Set uses_previous_context: true when the user is clearly following up on a previously
        discussed product or order. Otherwise false.
      PROMPT
    end

    def normalize_response(response)
      parsed  = JSON.parse(extract_json(response))
      primary = parsed["primary_intent"].to_s
      primary = VALID_INTENTS.include?(primary) ? primary : "general"

      {
        primary_intent:        primary,
        secondary_intents:     Array(parsed["secondary_intents"]).map(&:to_s),
        uses_previous_context: parsed["uses_previous_context"] == true
      }
    rescue
      fallback_response
    end

    def extract_json(text)
      text.to_s.match(/\{.*\}/m)&.to_s || "{}"
    end

    def fallback_response
      { primary_intent: "general", secondary_intents: [], uses_previous_context: false }
    end
  end
end
