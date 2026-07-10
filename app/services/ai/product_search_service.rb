module Ai
  class ProductSearchService
    LIMIT = 5

    def initialize(shop:, analyzed_query:)
      @shop           = shop
      @analyzed_query = analyzed_query || {}
    end

    def call
      scope = Product.includes(:product_variants).where(shop_id: @shop.id)

      # Product name is the primary signal — strict: no match means no results.
      scope = apply_product_name(scope)
      return [] unless scope.exists?

      # All remaining filters are soft narrows: applied only when they don't
      # empty the result set, so a misextracted attribute never kills a good search.
      scope = soft_apply(scope) { |s| apply_variant_name(s) }
      scope = soft_apply(scope) { |s| apply_attributes(s) }
      scope = soft_apply(scope) { |s| apply_tags(s) }
      scope = soft_apply(scope) { |s| apply_product_type(s) }
      scope = soft_apply(scope) { |s| apply_vendor(s) }
      scope = soft_apply(scope) { |s| apply_gender(s) }
      scope = soft_apply(scope) { |s| apply_price_filter(s) }
      scope = soft_apply(scope) { |s| apply_in_stock(s) }
      scope = soft_apply(scope) { |s| apply_collection(s) }

      scope = apply_sort(scope)

      scope.distinct.limit(LIMIT).to_a
    rescue StandardError => e
      Rails.logger.error("ProductSearchService Error: #{e.class} #{e.message}")
      []
    end

    private

    # Apply a filter; roll back if it empties the result.
    def soft_apply(scope)
      filtered = yield(scope)
      filtered.exists? ? filtered : scope
    end

    # =====================================
    # PRODUCT NAME — strict
    # =====================================
    def apply_product_name(scope)
      name = @analyzed_query[:product_name].presence || @analyzed_query[:keywords]
      return scope if name.blank?

      scope.where("products.title ILIKE ?", "%#{name}%")
    end

    # =====================================
    # VARIANT NAME — matches the combined variant title
    # e.g. "256GB Space Black", "Small Blue"
    # =====================================
    def apply_variant_name(scope)
      variant_name = @analyzed_query[:variant_name]
      return scope if variant_name.blank?

      scope.joins(:product_variants)
           .where("product_variants.title ILIKE ?", "%#{variant_name}%")
    end

    # =====================================
    # ATTRIBUTES — color, size, material, style, connectivity, storage, other
    # Each non-blank value is matched against the variant title.
    # =====================================
    def apply_attributes(scope)
      attributes = @analyzed_query[:attributes]
      return scope if attributes.blank?

      attributes.each_value do |value|
        next if value.blank?

        scope = scope.joins(:product_variants)
                     .where("product_variants.title ILIKE ?", "%#{value}%")
      end

      scope
    end

    # =====================================
    # TAGS (JSONB array)
    # =====================================
    def apply_tags(scope)
      tags = @analyzed_query[:tags]
      return scope if tags.blank?

      scope.where("products.tags ?| array[:tags]", tags: tags)
    end

    # =====================================
    # PRODUCT TYPE
    # =====================================
    def apply_product_type(scope)
      type = @analyzed_query[:product_type]
      return scope if type.blank?

      scope.where("products.product_type ILIKE ?", "%#{type}%")
    end

    # =====================================
    # VENDOR / BRAND
    # =====================================
    def apply_vendor(scope)
      vendor = @analyzed_query[:vendor]
      return scope if vendor.blank?

      scope.where("products.vendor ILIKE ?", "%#{vendor}%")
    end

    # =====================================
    # GENDER — matches tags or product_type
    # =====================================
    def apply_gender(scope)
      gender = @analyzed_query[:gender]
      return scope if gender.blank?

      normalized = gender.downcase

      scope.where(
        "products.product_type ILIKE :g OR products.tags::text ILIKE :g",
        g: "%#{normalized}%"
      )
    end

    # =====================================
    # PRICE RANGE
    # =====================================
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
      else
        scope.where("product_variants.price <= ?", max)
      end
    end

    # =====================================
    # IN STOCK FILTER
    # =====================================
    def apply_in_stock(scope)
      return scope unless @analyzed_query[:in_stock] == true

      scope.joins(:product_variants)
           .where("product_variants.inventory_quantity > 0")
    end

    # =====================================
    # COLLECTION (JSONB match)
    # =====================================
    def apply_collection(scope)
      collection = @analyzed_query[:collection]
      return scope if collection.blank?

      scope.where(
        "products.collections_data @> ?::jsonb",
        [ { title: collection } ].to_json
      )
    end

    # =====================================
    # SORT
    # =====================================
    def apply_sort(scope)
      case @analyzed_query[:sort_by]
      when "price_asc"
        scope.joins(:product_variants)
             .order("MIN(product_variants.price) ASC")
             .group("products.id")
      when "price_desc"
        scope.joins(:product_variants)
             .order("MIN(product_variants.price) DESC")
             .group("products.id")
      when "newest"
        scope.order(created_at: :desc)
      else
        scope
      end
    end
  end
end
