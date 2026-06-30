class ProductsDeleteJob < ApplicationJob
extend ShopifyAPI::Webhooks::WebhookHandler

queue_as :default

class << self
def handle(data:)
perform_later(
topic: data.topic,
shop_domain: data.shop,
webhook: data.body
)
end
end

def perform(topic:, shop_domain:, webhook:)
shop = Shop.find_by!(shopify_domain: shop_domain)


product = shop.products.find_by(
  shopify_product_id: webhook["id"].to_s
)

return unless product

product.destroy!
end
end
