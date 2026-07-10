module Ai
  class ProductRecommendationService
    LIMIT = 5

    def initialize(shop:, analyzed_query:, reference_product: nil)
      @shop             = shop
      @analyzed_query   = analyzed_query || {}
      @reference_product = reference_product
    end

    def call
      if @reference_product
        results = structured_similarity_search
        return results if results.size >= LIMIT

        rag = rag_search(exclude_ids: results.map(&:id))
        return (results + rag).first(LIMIT)
      end

      rag_search
    rescue StandardError => e
      Rails.logger.error("ProductRecommendationService Error: #{e.class} #{e.message}")
      []
    end

    private

    # ====================================================
    # STRUCTURED SEARCH — collection → product_type → tags
    # Only used when a reference product is available.
    # ====================================================
    def structured_similarity_search
      base  = in_stock_scope.where.not(id: @reference_product.id)
      found = []

      # 1. Same collections
      col_titles = Array(@reference_product.collections_data).filter_map { |c| c["title"] }.uniq
      if col_titles.any?
        conditions = col_titles.map { "collections_data @> ?::jsonb" }.join(" OR ")
        args       = col_titles.map { |t| [ { "title" => t } ].to_json }
        col_scope  = base.where("(#{conditions})", *args).where.not(id: found.map(&:id))
        found     |= col_scope.limit(LIMIT).to_a
      end

      return found.first(LIMIT) if found.size >= LIMIT

      # 2. Same product_type
      if @reference_product.product_type.present?
        type_scope = base.where(product_type: @reference_product.product_type)
                         .where.not(id: found.map(&:id))
        found     |= type_scope.limit(LIMIT - found.size).to_a
      end

      return found.first(LIMIT) if found.size >= LIMIT

      # 3. Same tags (any overlap)
      ref_tags = Array(@reference_product.tags).reject(&:blank?).first(10)
      if ref_tags.any?
        conditions = ref_tags.map { "tags @> ?::jsonb" }.join(" OR ")
        args       = ref_tags.map { |t| [ t ].to_json }
        tag_scope  = base.where("(#{conditions})", *args).where.not(id: found.map(&:id))
        found     |= tag_scope.limit(LIMIT - found.size).to_a
      end

      found.first(LIMIT)
    end

    # ====================================================
    # RAG SEARCH — embedding cosine similarity
    # ====================================================
    def rag_search(exclude_ids: [])
      scope = base_scope
      scope = apply_price_filter(scope)
      scope = apply_attribute_filter(scope)
      scope = scope.where.not(id: exclude_ids) if exclude_ids.any?

      return [] unless scope.exists?

      embedding = Ai::EmbeddingService.new.embed(build_query)

      ids =
        DocumentChunk
          .where(shop_id: @shop.id, source_type: "Product")
          .where(source_id: scope.select(:id))
          .nearest_neighbors(:embedding, embedding, distance: "cosine")
          .limit(LIMIT)
          .pluck(:source_id)

      Product.includes(:product_variants).where(id: ids)
    end

    # ====================================================
    # SCOPES
    # ====================================================
    def base_scope
      Product.includes(:product_variants).where(shop_id: @shop.id)
    end

    def in_stock_scope
      base_scope
        .joins(:product_variants)
        .where("product_variants.inventory_quantity > 0")
        .distinct
    end

    # ====================================================
    # FILTERS
    # ====================================================
    def apply_attribute_filter(scope)
      attributes = @analyzed_query[:attributes]
      return scope if attributes.blank?

      attributes.each_value do |value|
        next if value.blank?
        scope = scope.joins(:product_variants)
                     .where("product_variants.title ILIKE ?", "%#{value}%")
      end

      scope.distinct
    end

    def apply_price_filter(scope)
      price = @analyzed_query[:price_range]
      return scope if price.blank?

      min = price[:min]
      max = price[:max]
      return scope unless min || max

      scope = scope.joins(:product_variants)

      if min && max
        scope.where(product_variants: { price: min..max })
      elsif min
        scope.where("product_variants.price >= ?", min)
      elsif max
        scope.where("product_variants.price <= ?", max)
      else
        scope
      end
    end

    # ====================================================
    # EMBEDDING QUERY
    # ====================================================
    def build_query
      parts = []
      parts << @analyzed_query[:product_name]
      parts << @analyzed_query[:keywords]
      parts << @analyzed_query[:variant_name]
      parts << @analyzed_query[:product_type]
      parts << @analyzed_query[:vendor]
      parts << @analyzed_query[:gender]
      parts << @analyzed_query[:occasion]

      if @analyzed_query[:attributes].is_a?(Hash)
        parts += @analyzed_query[:attributes].values
      end

      parts << "gift for #{@analyzed_query[:gift_for]}" if @analyzed_query[:gift_for].present?

      # Enrich with reference product metadata for more targeted RAG
      if @reference_product
        parts << @reference_product.product_type
        parts << Array(@reference_product.tags).join(" ")
        parts << Array(@reference_product.collections_data).filter_map { |c| c["title"] }.join(" ")
      end

      parts.compact.reject(&:blank?).join(" ")
    end
  end
end
