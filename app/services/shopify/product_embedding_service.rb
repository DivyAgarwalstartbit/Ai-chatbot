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
      embedding = Ai::EmbeddingService.new.embed(content)

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
      parts = []
      parts << "Product Name: #{@product.title}"
      parts << "Description:\n#{clean_description}"             if clean_description.present?
      parts << "AI Info:\n#{@product.ai_info}"                  if @product.ai_info.present?
      parts << "Variants:\n#{variant_block}"                    if variant_block.present?
      parts << "Variant Attributes:\n#{variant_attributes.join(", ")}" if variant_attributes.any?
      parts << "Price Range:\n#{price_range}"                   if price_range.present?
      parts << "Availability:\n#{availability_summary}"
      parts << "Product Type:\n#{@product.product_type}"        if @product.product_type.present?
      parts << "Tags:\n#{Array(@product.tags).join(", ")}"      if Array(@product.tags).any?
      parts << "Collections:\n#{collection_names.join(", ")}"   if collection_names.any?
      parts << "Search Keywords:\n#{search_keywords.join(", ")}"
      parts.join("\n\n")
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

    def collection_names
      Array(@product.collections_data).filter_map { |c| c["title"] || c[:title] }.uniq
    end

    def search_keywords
      [
        @product.title,
        clean_description,
        @product.ai_info,
        @product.product_type,
        Array(@product.tags).join(" "),
        collection_names.join(" "),
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
