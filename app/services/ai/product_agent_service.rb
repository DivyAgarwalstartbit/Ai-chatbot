module Ai
class ProductAgentService
MATCH_THRESHOLD = 0.70


def initialize(shop:, message:)
 @shop = shop
 @message = message
end


def call
 chunks = search_products


 return no_products if chunks.empty?


 Ai::ChatGenerationService
 .new(
  message: @message,

  context:
   chunks.map(&:content).join("\n\n"),

  instructions:
  "
  You are a Shopify product assistant.

  Use ONLY context products.

  Show:
  - Product name
  - Price
  - Variants
  - Stock

  Never invent products.
  "
 )
 .call
end

private

def search_products
 embedding =
  Ai::OllamaEmbeddingService
  .new(@message)
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
  .limit(5)



 chunks.select do |chunk|
  chunk.neighbor_distance <
   MATCH_THRESHOLD
 end
end



def no_products
 "No matching products found."
end
end
end
