module Shopify
  class VariantEmbeddingService
    def initialize(variant)
      @variant = variant
      @product = variant.product
    end

    def call
      @variant.document_chunks.destroy_all

      content = build_chunk

      embedding = Ai::OllamaEmbeddingService.new(content).call

      DocumentChunk.create!(
        shop_id: @product.shop_id,
        source: @variant,
        source_type: "ProductVariant",
        source_id: @variant.id,
        chunk_index: 0,
        content: content,
        embedding: embedding,
        embedded_at: Time.current
      )
    end

    private

    def build_chunk
      <<~TEXT
        Product: #{@product.title}

        Variant: #{@variant.title}

        Options:
        #{options_text}

        Price: #{@variant.price}

        Compare At Price: #{@variant.compare_at_price}

        Stock: #{@variant.inventory_quantity}

        Availability: #{@variant.available ? "In stock" : "Out of stock"}

        SKU: #{@variant.sku}

        Product Context:
        #{@product.title} - #{@product.ai_info}
      TEXT
    end

    def options_text
      Array(@variant.options)
        .map { |o| "#{o["name"]}: #{o["value"]}" }
        .join(", ")
    end
  end
end
