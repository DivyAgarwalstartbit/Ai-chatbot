module Shopify
class ProductEmbeddingService
def initialize(product)
 @product = product
end



def call
  @product.document_chunks.destroy_all
  chunks_data = build_chunks

  chunks_data.each do |chunk_text|
    embedding = Ai::OllamaEmbeddingService.new(chunk_text).call

    DocumentChunk.create!(
      shop_id:   @product.shop_id,
      source:    @product,
      content:   chunk_text,
      embedding: embedding
    )
  end
end

private

def build_chunks
  chunks = []

  # Chunk 1 — Product overview
  chunks << <<~TEXT
    Product Name: #{@product.title}
    Description: #{@product.description}
    Handle: #{@product.handle}
  TEXT

  # Chunk 2+ — Har variant alag chunk
  @product.product_variants.each do |v|
    chunks << <<~TEXT
      Product: #{@product.title}
      Variant: #{v.title}
      Price: #{v.price}
      Stock: #{v.inventory_quantity}
      Options: #{v.options}
    TEXT
  end

  chunks
end
end
end
