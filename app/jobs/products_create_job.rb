class ProductsCreateJob < ApplicationJob
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

    payload =
    webhook.is_a?(String) ? JSON.parse(webhook) : webhook


  Shopify::ProductSyncService.new(
    shop: shop,
    product_id: payload["id"]
  ).call
  end
end
