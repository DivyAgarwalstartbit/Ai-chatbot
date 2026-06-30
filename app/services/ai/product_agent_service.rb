module Ai
  class ProductAgentService
    DISPLAY_LIMIT = 3

    def initialize(shop:, message:, intent:, memory:, stream_callback: nil)
      @shop            = shop
      @message         = message.to_s.strip
      @intent          = intent || {}
      @memory          = memory
      @stream_callback = stream_callback
    end

    # ==================================================
    # ENTRY POINT
    # ==================================================
    def call
      return comparison_response if @intent[:primary_intent] == "product_comparison"

      analyzed_query = analyze_query
      save_query_state(analyzed_query)

      # When the user names a specific product, always do the exact-product flow.
      return named_product_flow(analyzed_query) if analyzed_query[:product_name].present?

      # Follow-up about a product already in context (no new name/keywords)
      return product_detail_response       if detail_intent?
      return answer_from_existing_product  if answerable_from_context?(analyzed_query)

      # If the query carries no searchable signal, ask for clarification rather
      # than dumping random recommendations the user didn't ask for.
      return clarify_response if query_too_vague?(analyzed_query)

      # Keyword / attribute / category search
      keyword_search_flow(analyzed_query)
    rescue StandardError => e
      Rails.logger.error("ProductAgentService Error: #{e.class} #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      empty_response
    end

    private

    # ==================================================
    # QUERY ANALYSIS
    # ==================================================
    def analyze_query
      Ai::ProductQueryAnalyzerService.new(
        message:               @message,
        previous_data:         last_query_hash,
        uses_previous_context: @intent[:uses_previous_context],
        shop:                  @shop
      ).call
    end

    # ==================================================
    # NAMED PRODUCT FLOW
    # The user mentioned a specific product name.
    # ==================================================
    def named_product_flow(analyzed_query)
      products = Ai::ProductSearchService.new(shop: @shop, analyzed_query: analyzed_query).call

      if products.blank?
        # Product name not found in catalogue
        @memory.set_awaiting_recommendation(analyzed_query, "not_found")
        return {
          success:  true,
          type:     "text",
          message:  "I couldn't find \"#{analyzed_query[:product_name]}\" in our store. " \
                    "Would you like me to recommend similar products?",
          products: []
        }
      end

      product = products.first

      if out_of_stock?(product)
        # Found but fully out of stock — show the card and ask
        save_product_context(product)
        @memory.set_awaiting_recommendation(analyzed_query, "out_of_stock")
        return {
          success:  true,
          type:     "product_cards",
          message:  "\"#{product.title}\" is currently unavailable. " \
                    "Would you like me to recommend similar products?",
          products: build_cards([ product ])
        }
      end

      # Found and in stock — show up to DISPLAY_LIMIT cards
      product_response(products.first(DISPLAY_LIMIT), analyzed_query)
    end

    # ==================================================
    # KEYWORD / CATEGORY SEARCH FLOW
    # No specific product name — broad search then recommendations.
    # ==================================================
    def keyword_search_flow(analyzed_query)
      products = Ai::ProductSearchService.new(shop: @shop, analyzed_query: analyzed_query).call

      if products.blank?
        # Only recommend when we have enough signal to find relevant items.
        # Without it we'd surface random products the user never asked for.
        return clarify_response if query_too_vague?(analyzed_query)

        recommendations = Ai::ProductRecommendationService.new(
          shop: @shop, analyzed_query: analyzed_query
        ).call.first(DISPLAY_LIMIT)

        return empty_response if recommendations.blank?

        save_product_context(recommendations.first)

        message = Ai::ChatGenerationService.new(
          message:         @message,
          context:         build_product_context(recommendations),
          shop:            @shop,
          stream_callback: @stream_callback,
          instructions:    "No exact match found. Present these recommendations briefly — 1-2 sentences."
        ).call

        return response(message: message, products: build_cards(recommendations))
      end

      product_response(products.first(DISPLAY_LIMIT), analyzed_query)
    end

    # ==================================================
    # PRODUCT DETAIL — answer from the product in memory
    # ==================================================
    def detail_intent?
      @intent[:primary_intent] == "product_detail" && last_product_hash.present?
    end

    def product_detail_response
      product = last_product_hash
      return empty_response if product.blank?

      message = Ai::ChatGenerationService.new(
        message:         @message,
        context:         build_detail_context(product),
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    <<~TEXT
          Answer ONLY from the product data above.
          - If the user asks about variants, size, or color — list ALL available options.
          - Include prices and stock status.
          - Be specific, complete, and concise (3-4 sentences max).
          - Never invent information not present in the data.
        TEXT
      ).call

      { success: true, type: "product_cards", message: message, products: [ product_card_from_hash(product) ] }
    end

    # ==================================================
    # CONTEXT CHECK — follow-up with no new search signal
    # ==================================================
    def answerable_from_context?(analyzed_query)
      return false unless @intent[:uses_previous_context]

      product = last_product_hash
      return false if product.blank?

      analyzed_query[:product_name].blank? &&
        analyzed_query[:keywords].blank? &&
        analyzed_query[:gift_for].blank? &&
        (analyzed_query[:attributes].blank? || analyzed_query[:attributes].values.all?(&:blank?)) &&
        (analyzed_query.dig(:price_range, :min).blank? && analyzed_query.dig(:price_range, :max).blank?)
    end

    def answer_from_existing_product
      product = last_product_hash
      return empty_response if product.blank?

      message = Ai::ChatGenerationService.new(
        message:         @message,
        context:         build_detail_context(product),
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    "Answer ONLY from the product data above. Never invent information. If unavailable, say so."
      ).call

      { success: true, type: "product_cards", message: message, products: [ product_card_from_hash(product) ] }
    end

    # ==================================================
    # PRODUCTS FOUND — show up to 3 cards
    # ==================================================
    def product_response(products, _analyzed_query)
      save_product_context(products.first)

      message = Ai::ChatGenerationService.new(
        message:         @message,
        context:         build_product_context(products),
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    <<~TEXT
          You are a helpful e-commerce assistant.
          - Answer exactly what the user asked using ONLY the product data above.
          - Mention key details (price, variants, stock) naturally.
          - Keep it concise — 2-3 sentences max.
          - Do not invent specifications.
        TEXT
      ).call

      response(message: message, products: build_cards(products))
    end

    def out_of_stock?(product)
      product.product_variants.all? { |v| v.inventory_quantity.to_i <= 0 }
    end

    # ==================================================
    # COMPARISON — two products side by side
    # ==================================================
    def comparison_response
      analyzed = Ai::ProductQueryAnalyzerService.new(
        message:               @message,
        previous_data:         last_query_hash,
        uses_previous_context: false
      ).call

      products = Ai::ProductSearchService.new(shop: @shop, analyzed_query: analyzed).call
      products = Ai::ProductRecommendationService.new(shop: @shop, analyzed_query: analyzed).call if products.blank?

      return empty_response if products.blank?

      compared = products.first(2)
      save_product_context(compared.first)

      message = Ai::ChatGenerationService.new(
        message:         @message,
        context:         build_product_context(compared),
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    <<~TEXT
          The user wants to compare products. Use ONLY the product data above.
          - Highlight key differences: price, variants, stock availability.
          - Give a clear recommendation at the end if possible.
          - Keep it concise and structured.
        TEXT
      ).call

      response(message: message, products: build_cards(compared))
    end

    # ==================================================
    # MEMORY — JSON-safe read/write
    # ==================================================
    def last_query_hash
      raw = @memory.get_context("last_query_json")
      return {} if raw.blank?

      JSON.parse(raw).deep_symbolize_keys
    rescue JSON::ParserError
      {}
    end

    def last_product_hash
      raw = @memory.get_context("last_product_json")
      return nil if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    def save_query_state(analyzed_query)
      @memory.set_context("last_query_json", analyzed_query.to_json)
    end

    def save_product_context(product)
      return unless product

      serialized = serialize_product(product)
      @memory.set_context("last_product_id",   product.id)
      @memory.set_context("last_product_title", product.title)
      @memory.set_context("last_product_json",  serialized.to_json)
      @memory.add_product(product)
    end

    # ==================================================
    # CONTEXT BUILDERS
    # ==================================================
    def build_product_context(products)
      products.map do |p|
        <<~TEXT
          Product: #{p.title}
          Variants:
          #{p.product_variants.map { |v| "- #{v.title} | Price: #{v.price} | Stock: #{v.inventory_quantity}" }.join("\n")}
        TEXT
      end.join("\n---\n")
    end

    # Builds context from the stored JSON hash (no DB hit needed)
    def build_detail_context(product_hash)
      variants = Array(product_hash["variants"]).map do |v|
        stock_label = v["stock"].to_i > 0 ? "In Stock (#{v["stock"]})" : "Out of Stock"
        "- #{v["title"]} | Price: #{v["price"]} | #{stock_label}"
      end.join("\n")

      <<~TEXT
        Product: #{product_hash["title"]}
        Handle:  #{product_hash["handle"]}
        Variants:
        #{variants}
      TEXT
    end

    # ==================================================
    # SERIALIZERS
    # ==================================================
    def serialize_product(product)
      {
        "id"        => product.id,
        "title"     => product.title,
        "handle"    => product.handle,
        "image_url" => product.image_url,
        "variants"  => product.product_variants.map do |v|
          {
            "id"                 => v.id,
            "shopify_variant_id" => v.shopify_variant_id,
            "title"              => v.title,
            "price"              => v.price,
            "stock"              => v.inventory_quantity
          }
        end
      }
    end

    def build_cards(products)
      products.map { |p| product_card(p) }
    end

    def product_card(product)
      {
        id:       product.id,
        title:    product.title,
        image:    product.image_url,
        handle:   product.handle,
        variants: product.product_variants.map do |v|
          {
            id:                 v.id,
            shopify_variant_id: v.shopify_variant_id,
            title:              v.title,
            price:              v.price,
            stock:              v.inventory_quantity
          }
        end
      }
    end

    def product_card_from_hash(product_hash)
      {
        id:       product_hash["id"],
        title:    product_hash["title"],
        image:    product_hash["image_url"],
        handle:   product_hash["handle"],
        variants: Array(product_hash["variants"]).map do |v|
          {
            id:                 v["id"],
            shopify_variant_id: v["shopify_variant_id"],
            title:              v["title"],
            price:              v["price"],
            stock:              v["stock"]
          }
        end
      }
    end

    # ==================================================
    # RESPONSE HELPERS
    # ==================================================
    def response(message:, products:)
      { success: true, type: "product_cards", message: message, products: products }
    end

    # ==================================================
    # VAGUE QUERY GUARD
    # A query is "too vague" when the analyzer couldn't extract any searchable
    # signal: no name, no keywords, no type, no vendor, no gift/occasion context,
    # no attributes, and no price range. Surfacing random products in this case
    # would feel irrelevant, so we ask for clarification instead.
    # ==================================================
    def query_too_vague?(analyzed_query)
      analyzed_query[:product_name].blank? &&
        analyzed_query[:keywords].blank? &&
        analyzed_query[:product_type].blank? &&
        analyzed_query[:vendor].blank? &&
        analyzed_query[:gift_for].blank? &&
        analyzed_query[:occasion].blank? &&
        analyzed_query.dig(:price_range, :min).blank? &&
        analyzed_query.dig(:price_range, :max).blank? &&
        (analyzed_query[:attributes].blank? ||
          analyzed_query[:attributes].values.all?(&:blank?))
    end

    def clarify_response
      {
        success:  true,
        type:     "text",
        message:  "I'd love to help you find the right product! Could you give me a bit more detail? " \
                  "For example — what type of product are you looking for, a brand you prefer, " \
                  "a color or size, or a budget range?",
        products: []
      }
    end

    def empty_response
      {
        success:  true,
        type:     "text",
        message:  "I couldn't find any matching products. Could you describe what you're looking for?",
        products: []
      }
    end
  end
end
