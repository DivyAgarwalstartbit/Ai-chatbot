module Ai
  class ConversationLimitError < StandardError; end
  class MessageLimitError < StandardError; end

  class MemoryService
    RECENT_LIMIT  = 6
    SUMMARY_AFTER = 20
    MAX_PRODUCTS  = 5
    STALE_AFTER   = 4.days

    attr_reader :conversation

    def initialize(shop:, customer:, session_id:)
      @conversation = find_or_start_conversation(shop, customer, session_id)
    end

    # =========================
    # CONTEXT FOR LLM
    # =========================
    def context
      parts = []
      parts << "Summary:\n#{summary}"               if summary.present?
      parts << "Last Intent: #{last_intent&.dig("primary_intent")}" if last_intent.present?
      parts << "Recent Messages:\n#{recent_messages_text}"
      parts << "Last Products Discussed:\n#{formatted_last_products}" if last_products.any?
      parts.join("\n\n")
    end

    # Compact recent messages text — used by IntentService for context-aware classification
    def recent_messages_text
      @conversation.messages
        .order(created_at: :desc)
        .limit(RECENT_LIMIT)
        .reverse
        .map { |m| "#{m.role.capitalize}: #{m.content}" }
        .join("\n")
    end

    # =========================
    # MESSAGE SAVE
    # =========================
    def add(role:, content:, metadata: nil, shop: nil)
      return if content.blank?

      enforce_message_limit!(shop) if role == "user" && shop.present?

      @conversation.messages.create!(role: role, content: content, metadata: metadata)
      @conversation.update_column(:last_message_at, Time.current)
      schedule_summary
    end

    # =========================
    # REDIS CONTEXT SET / GET
    # get_context()      → full hash of all keys
    # get_context("key") → raw string value for that key
    # =========================
    def set_context(key, value)
      all = Rails.cache.read(context_key) || {}
      all[key.to_s] = value
      Rails.cache.write(context_key, all, expires_in: 7.days)
    end

    def get_context(key = nil)
      all = Rails.cache.read(context_key) || {}
      key.present? ? all[key.to_s] : all
    end

    # =========================
    # LAST INTENT STORAGE
    # =========================
    def last_intent
      raw = get_context("last_intent_json")
      raw.present? ? JSON.parse(raw) : nil
    end

    def set_last_intent(intent_hash)
      return if intent_hash.blank?

      set_context("last_intent_json", intent_hash.to_json)
    end

    # =========================
    # LAST PRODUCT HELPERS
    # =========================
    def last_product_id
      get_context("last_product_id")&.to_i
    end

    def last_product_title
      get_context("last_product_title")
    end

    # =========================
    # LAST 5 PRODUCTS
    # =========================
    def last_products
      raw = get_context("last_5_products")
      raw.present? ? JSON.parse(raw) : []
    end

    def add_product(product)
      return unless product

      products = last_products

      new_entry = {
        "id"     => product.id,
        "title"  => product.title,
        "handle" => product.handle,
        "variants" => product.product_variants.map do |v|
          {
            "id"                 => v.id,
            "title"              => v.title,
            "sku"                => v.sku,
            "price"              => v.price,
            "compare_at_price"   => v.compare_at_price,
            "inventory_quantity" => v.inventory_quantity,
            "available"          => v.available
          }
        end
      }

      products.reject! { |p| p["id"] == product.id }
      products << new_entry
      products = products.last(MAX_PRODUCTS)

      set_context("last_5_products", products.to_json)
    end

    def set_active_product(product)
      return unless product

      set_context("last_product_id", product.id)
      set_context("last_product_title", product.title)
      add_product(product)
    end

    # =========================
    # RECOMMENDATION CONFIRMATION STATE
    # Set when the bot asks "want me to recommend similar?"
    # and cleared once the user answers yes or no.
    # =========================
    def awaiting_recommendation?
      get_context("awaiting_product_recommendation") == "true"
    end

    def set_awaiting_recommendation(analyzed_query, reason)
      set_context("awaiting_product_recommendation",  "true")
      set_context("pending_recommendation_query",     analyzed_query.to_json)
      set_context("pending_recommendation_reason",    reason.to_s)
    end

    def clear_recommendation_wait
      all = Rails.cache.read(context_key) || {}
      all.delete("awaiting_product_recommendation")
      all.delete("pending_recommendation_query")
      all.delete("pending_recommendation_reason")
      Rails.cache.write(context_key, all, expires_in: 7.days)
    end

    def pending_recommendation_query
      raw = get_context("pending_recommendation_query")
      return {} if raw.blank?

      JSON.parse(raw).deep_symbolize_keys
    rescue JSON::ParserError
      {}
    end

    def pending_recommendation_reason
      get_context("pending_recommendation_reason").presence || "not_found"
    end

    # =========================
    # ACTIVE ORDER
    # =========================
    def active_order
      raw = get_context("active_order")
      raw.present? ? JSON.parse(raw) : nil
    end

    def set_active_order(order)
      set_context("active_order", order.to_json)
    end

    def clear_active_order
      all = Rails.cache.read(context_key) || {}
      all.delete("active_order")
      Rails.cache.write(context_key, all, expires_in: 7.days)
    end

    private

    def enforce_message_limit!(shop)
      limit = shop.effective_message_limit
      return if limit.nil?

      if shop.free?
        # Free: 50 messages total across ALL conversations this month
        monthly_conv_ids = shop.conversations
                               .where(created_at: Time.current.beginning_of_month..)
                               .pluck(:id)
        user_msg_count = Message.where(conversation_id: monthly_conv_ids, role: "user").count
        if user_msg_count >= limit
          raise MessageLimitError, "You've reached your monthly message limit (#{limit} messages). Upgrade to continue chatting."
        end
      else
        # Starter / Pro: hard cap per conversation
        user_msg_count = @conversation.messages.where(role: "user").count
        if user_msg_count >= limit
          raise MessageLimitError, "You've reached the #{limit}-message limit for this conversation. Please start a new conversation to continue."
        end
      end
    end

    def formatted_last_products
      last_products.map { |p| "- #{p["title"]} (id: #{p["id"]})" }.join("\n")
    end

    # =========================
    # SUMMARY
    # =========================
    def summary
      Rails.cache.read(summary_key)
    end

    def schedule_summary
      count = @conversation.messages.count
      return if count < SUMMARY_AFTER
      return unless count % 5 == 0

      MemorySummaryJob.perform_later(@conversation.id)
    end

    def context_key
      "ai:ctx:conversation:#{@conversation.id}"
    end

    def summary_key
      "ai:summary:conversation:#{@conversation.id}"
    end

    # =========================
    # CONVERSATION LIFECYCLE
    # =========================
    def find_or_start_conversation(shop, customer, session_id)
      existing = Conversation.find_by(shop: shop, customer: customer, session_id: session_id)

      # Reuse an open, non-stale conversation
      return existing if existing && existing.status != "closed" && !stale?(existing)

      # Free/Starter: hard block at conversation limit
      if !shop.pro? && shop.conversations.where(created_at: Time.current.beginning_of_month..).count >= shop.effective_conversation_limit
        notify_limit_reached(shop, :conversation) if shop.starter?
        raise ConversationLimitError, "Monthly conversation limit reached. Upgrade to Pro to continue."
      end

      # Allow the conversation through
      conv = Conversation.create!(
        shop:       shop,
        customer:   customer,
        session_id: SecureRandom.uuid,
        status:     "open",
        started_at: Time.current
      )

      # If this is a "continue with context" reset, inject the previous summary
      pending_ctx = Rails.cache.read("ai:pending_context:#{session_id}")
      if pending_ctx.present?
        Rails.cache.write("ai:summary:conversation:#{conv.id}", pending_ctx, expires_in: 7.days)
        Rails.cache.delete("ai:pending_context:#{session_id}")
      end

      # Pro: if count now exceeds limit, auto-charge overage (non-blocking — charge happens async-safe)
      if shop.overage_eligible? && shop.conversations.where(created_at: Time.current.beginning_of_month..).count > shop.effective_conversation_limit
        OverageService.new(shop: shop, resource_type: :conversation).check_and_charge!
      end

      conv
    end

    def stale?(conv)
      threshold = conv.last_message_at || conv.created_at
      threshold < STALE_AFTER.ago
    end

    def notify_limit_reached(shop, resource)
      cache_key = "limit_email:#{shop.id}:#{resource}:#{Date.current}"
      return if Rails.cache.exist?(cache_key)
      Rails.cache.write(cache_key, true, expires_in: 1.day)
      LimitReachedMailer.limit_reached(shop: shop, resource: resource).deliver_later
    end
  end
end
