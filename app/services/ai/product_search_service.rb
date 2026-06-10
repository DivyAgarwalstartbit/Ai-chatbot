module Ai
class ProductSearchService
VECTOR_LIMIT = 10
MATCH_THRESHOLD = 0.50


def initialize(
 shop:,
 query:
)
 @shop = shop
 @query = query
end


def call
results =
 (
  vector_search +
  keyword_search
 )
 .uniq



results
end
private







# =====================
# Semantic Search
# =====================


def vector_search
embedding =
 Ai::OllamaEmbeddingService
 .new(@query)
 .call



chunks =
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
 .limit(VECTOR_LIMIT)

valid =
 chunks.select do |chunk|
 chunk.neighbor_distance <
 MATCH_THRESHOLD
end

Product
.includes(
 :product_variants
)
.where(
 id: valid.map(&:source_id)
)
end

# =====================
# SQL fallback
# =====================


def keyword_search
Product
.includes(
 :product_variants
)
.left_joins(
 :product_variants
)
.where(
 shop_id: @shop.id
)
.where(
"
products.title ILIKE :q

OR

products.handle ILIKE :q

OR

product_variants.title ILIKE :q

OR

product_variants.options::text ILIKE :q
",

q: "%#{@query}%"

)
end
end
end
