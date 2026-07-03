module Ai
  class ProductRecommendationService
    LIMIT = 5

    def initialize(shop:, analyzed_query:)
      @shop = shop
      @analyzed_query = analyzed_query || {}
    end

    def call
      scope =
        Product
          .includes(:product_variants)
          .where(shop_id: @shop.id)

      scope = apply_price_filter(scope)
      scope = apply_attribute_filter(scope)

      return [] unless scope.exists?

      embedding = Ai::EmbeddingService.new.embed(build_query)

      ids =
        DocumentChunk
          .where(
            shop_id: @shop.id,
            source_type: "Product"
          )
          .where(
            source_id: scope.select(:id)
          )
          .nearest_neighbors(
            :embedding,
            embedding,
            distance: "cosine"
          )
          .limit(LIMIT)
          .pluck(:source_id)

      Product
        .includes(:product_variants)
        .where(id: ids)
    rescue StandardError => e
      Rails.logger.error(
        "ProductRecommendationService Error: #{e.class} #{e.message}"
      )

      []
    end

    private

    # =====================================
    # ATTRIBUTE FILTER
    # =====================================

    def apply_attribute_filter(scope)
      attributes = @analyzed_query[:attributes]

      return scope if attributes.blank?

      attributes.each_value do |value|
        next if value.blank?

        scope =
          scope
            .joins(:product_variants)
            .where(
              "product_variants.title ILIKE ?",
              "%#{value}%"
            )
      end

      scope.distinct
    end

    # =====================================
    # PRICE FILTER
    # =====================================

    def apply_price_filter(scope)
      price = @analyzed_query[:price_range]

      return scope if price.blank?

      min = price[:min]
      max = price[:max]

      return scope unless min || max

      scope = scope.joins(:product_variants)

      if min && max
        scope.where(
          product_variants: {
            price: min..max
          }
        )
      elsif min
        scope.where(
          "product_variants.price >= ?",
          min
        )
      elsif max
        scope.where(
          "product_variants.price <= ?",
          max
        )
      else
        scope
      end
    end

    # =====================================
    # EMBEDDING QUERY
    # =====================================

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

      parts.compact.reject(&:blank?).join(" ")
    end
  end
end
