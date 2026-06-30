module Ai
  class ProductRecommendationAgentService
    def initialize(shop:, message:, intent:, memory:, stream_callback: nil)
      @shop            = shop
      @message         = message.to_s.strip
      @intent          = intent || {}
      @memory          = memory
      @stream_callback = stream_callback
    end

    def call
      analyzed_query = Ai::ProductQueryAnalyzerService.new(
        message:               @message,
        previous_data:         last_query_hash,
        uses_previous_context: @intent[:uses_previous_context]
      ).call

      @memory.set_context("last_query_json", analyzed_query.to_json)

      products = Ai::ProductRecommendationService.new(
        shop:           @shop,
        analyzed_query: analyzed_query
      ).call

      return empty_response if products.blank?

      products.each { |p| @memory.add_product(p) }

      context = build_product_context(products)
      message = Ai::ChatGenerationService.new(
        message:         @message,
        context:         context,
        shop:            @shop,
        stream_callback: @stream_callback,
        instructions:    <<~TEXT
          The user is looking for recommendations. Using ONLY the product data above:
          - Suggest the most relevant options with a brief reason why.
          - Mention price and availability naturally.
          - Keep it conversational and concise (2-3 sentences).
        TEXT
      ).call

      {
        success:  true,
        type:     "product_cards",
        message:  message,
        products: build_cards(products)
      }
    rescue StandardError => e
      Rails.logger.error("ProductRecommendationAgentService Error: #{e.class} #{e.message}")
      empty_response
    end

    private

    def last_query_hash
      raw = @memory.get_context("last_query_json")
      return {} if raw.blank?

      JSON.parse(raw).deep_symbolize_keys
    rescue JSON::ParserError
      {}
    end

    def build_product_context(products)
      products.map do |p|
        <<~TEXT
          Product: #{p.title}
          Variants:
          #{p.product_variants.map { |v| "- #{v.title} | Price: #{v.price} | Stock: #{v.inventory_quantity}" }.join("\n")}
        TEXT
      end.join("\n---\n")
    end

    def build_cards(products)
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

    def empty_response
      {
        success:  true,
        type:     "product_cards",
        message:  "I couldn't find specific recommendations right now. Try describing what you're looking for in more detail.",
        products: []
      }
    end
  end
end
