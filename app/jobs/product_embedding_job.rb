class ProductEmbeddingJob < ApplicationJob
queue_as :default



def perform(product_id)
 product =
 Product.find(product_id)



 Shopify::ProductEmbeddingService
 .new(product)
 .call
end
end
