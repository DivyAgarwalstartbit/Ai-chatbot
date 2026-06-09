module Ai
class ProductRecommendationService
LIMIT = 3



def initialize(
 shop:,
 query: nil,
 product: nil
)
 @shop = shop
 @query = query
 @product = product
end


def call
if @product.present?

 similar_products

else

 query_based_products

end
end

private

# =========================
# Similar products
# =========================


def similar_products
chunk =
 DocumentChunk
 .find_by(
  shop_id: @shop.id,
  source_type: "Product",
  source_id: @product.id
 )


return fallback_products unless chunk

ids =
 DocumentChunk
 .where(
  shop_id: @shop.id,
  source_type: "Product"
 )
 .where
 .not(
  source_id: @product.id
 )
 .nearest_neighbors(
  :embedding,
  chunk.embedding,
  distance: "cosine"
 )
 .limit(LIMIT)
 .pluck(
  :source_id
 )

Product
.includes(
 :product_variants
)
.where(
 id: ids
)
end


# =========================
# Requirement / gift search
# =========================


def query_based_products
embedding =
 Ai::OllamaEmbeddingService
 .new(@query)
 .call




ids =
 DocumentChunk
 .where(
  shop_id: @shop.id,
  source_type: "Product"
 )
 .nearest_neighbors(
  :embedding,
  embedding,
  distance: "cosine"
 )
 .limit(LIMIT)
 .pluck(
  :source_id
 )

Product
.includes(
 :product_variants
)
.where(
 id: ids
)
end


def fallback_products
Product
.includes(
 :product_variants
)
.where(
 shop_id: @shop.id
)
.limit(LIMIT)
end
end
end
