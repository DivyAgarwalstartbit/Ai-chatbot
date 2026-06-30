class ProductEmbeddingJob < ApplicationJob
queue_as :default



def perform(product_id)
 product =
 Product.find(product_id)



 Shopify::ProductEmbeddingService
 .new(product)
 .call

 product.product_variants.find_each do |variant|
  Shopify::VariantEmbeddingService.new(variant).call
end
end
end
