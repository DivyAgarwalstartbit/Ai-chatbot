module Shopify
  class ProductEmbeddingService
    def initialize(product)
      @product = product
    end

    def call
      trace      = build_trace
      started_at = Time.current

      @product.document_chunks.destroy_all

      content   = build_product_chunk
      embedding = Ai::OllamaEmbeddingService.new(content).call

      chunk = DocumentChunk.create!(
        shop_id:     @product.shop_id,
        source:      @product,
        source_type: "Product",
        source_id:   @product.id,
        chunk_index: 0,
        content:     content,
        embedding:   embedding,
        embedded_at: Time.current
      )

      Langfuse.span(
        trace_id: trace.id,
        name:     "product_embedding/embed",
        input:    { product_id: @product.id, title: @product.title },
        output:   { chunk_id: chunk.id, content_length: content.length },
        end_time: Time.now.utc,
        metadata: { latency_ms: elapsed_ms(started_at) }
      )

      chunk
    rescue => e
      log_error(trace, "product_embedding/embed", e)
      raise
    ensure
      Langfuse.flush
    end

    private

    def build_trace
      Langfuse.trace(
        name:       "product_embedding",
        user_id:    Ai::LangfuseContext.user_id,
        session_id: Ai::LangfuseContext.session_id,
        metadata:   { shop: Ai::LangfuseContext.shop, product_id: @product.id }.compact
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

    def build_product_chunk
      <<~TEXT
        Product Name: #{@product.title}

        Description:
        #{clean_description}

        AI Info:
        #{@product.ai_info}

        Variants:
        #{variant_block}

        Variant Attributes:
        #{variant_attributes.join(", ")}

        Price Range:
        #{price_range}

        Availability:
        #{availability_summary}

        Search Keywords:
        #{search_keywords.join(", ")}
      TEXT
    end

    def clean_description
      ActionView::Base.full_sanitizer.sanitize(@product.description.to_s)
    end

    def variant_block
      @product.product_variants.map do |v|
        opts = Array(v.options)
          .map { |o| "#{o["name"]}: #{o["value"]}" }
          .join(" | ")

        "Title: #{v.title} | #{opts} | Price: #{v.price} | Stock: #{v.inventory_quantity}"
      end.join("\n")
    end

    def variant_attributes
      attrs = []

      @product.product_variants.find_each do |variant|
        Array(variant.options).each do |opt|
          name  = opt["name"].to_s.strip.downcase
          value = opt["value"].to_s.strip

          next if name.blank? || value.blank?

          attrs << "#{name}: #{value}"
        end
      end

      attrs.uniq
    end

    def price_range
      prices = @product.product_variants.map(&:price).compact
      return "" if prices.empty?

      "₹#{prices.min} - ₹#{prices.max}"
    end

    def availability_summary
      in_stock = @product.product_variants.any?(&:available)
      in_stock ? "In Stock" : "Out of Stock"
    end

    def search_keywords
      [
        @product.title,
        clean_description,
        @product.ai_info,
        variant_attributes.join(" "),
        variant_titles.join(" ")
      ]
        .join(" ")
        .downcase
        .scan(/[a-z0-9]+/)
        .uniq
        .first(100)
    end

    def variant_titles
      @product.product_variants.pluck(:title).uniq
    end
  end
end
