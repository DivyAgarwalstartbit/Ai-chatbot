class ProductsUpdateJob < ApplicationJob
extend ShopifyAPI::Webhooks::WebhookHandler
Rails.logger.info("🔥 UPDATE WEBHOOK HIT")
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

payload =
    webhook.is_a?(String) ? JSON.parse(webhook) : webhook


Shopify::ProductSyncService.new(
  shop: shop,
  product_id: payload["id"]
).call

shop.update_column(:products_synced_at, Time.current)
end
end
