class ProductsUpdateJob < ApplicationJob
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

    payload = webhook.is_a?(String) ? JSON.parse(webhook) : webhook

    shopify_product_id = payload["id"].to_s
    product_exists_locally = shop.products.exists?(shopify_product_id: shopify_product_id)

    # If the product doesn't exist locally yet, treat it like a create — enforce limit
    unless product_exists_locally || shop.pro?
      if shop.products.count >= shop.effective_product_limit
        Rails.logger.info("ProductsUpdateJob: product limit reached for #{shop_domain} [#{shop.plan_label}] — skipping new product #{shopify_product_id}")
        return
      end
    end

    Shopify::ProductSyncService.new(shop: shop, product_id: payload["id"]).call
    shop.update_column(:products_synced_at, Time.current)
  end
end