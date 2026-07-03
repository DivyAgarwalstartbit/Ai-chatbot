module Shopify
  class VariantEmbeddingService
    def initialize(variant)
      @variant = variant
      @product = variant.product
    end

    def call
      trace      = build_trace
      started_at = Time.current

      @variant.document_chunks.destroy_all

      content   = build_chunk
      embedding = Ai::OllamaEmbeddingService.new(content).call

      chunk = DocumentChunk.create!(
        shop_id:     @product.shop_id,
        source:      @variant,
        source_type: "ProductVariant",
        source_id:   @variant.id,
        chunk_index: 0,
        content:     content,
        embedding:   embedding,
        embedded_at: Time.current
      )

      Langfuse.span(
        trace_id:  trace.id,
        name:      "variant_embedding/embed",
        input:     { variant_id: @variant.id, product: @product.title, variant: @variant.title },
        output:    { chunk_id: chunk.id, content_length: content.length },
        end_time:  Time.now.utc,
        metadata:  { latency_ms: elapsed_ms(started_at) }
      )

      chunk
    rescue => e
      log_error(trace, "variant_embedding/embed", e)
      raise
    ensure
      Langfuse.flush
    end

    private

    def build_trace
      Langfuse.trace(
        name:       "variant_embedding",
        user_id:    Ai::LangfuseContext.user_id,
        session_id: Ai::LangfuseContext.session_id,
        metadata:   { shop: Ai::LangfuseContext.shop, variant_id: @variant.id, product_id: @product.id }.compact
      )
    end

    def log_error(trace, name, error)
      return unless trace
      Langfuse.span(
        trace_id:       trace.id,
        name:           name,
        end_time:       Time.now.utc,
        level:          "ERROR",
        status_message: error.message
      )
    rescue StandardError
      nil
    end

    def elapsed_ms(started_at)
      ((Time.current - started_at) * 1000).round
    end

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
