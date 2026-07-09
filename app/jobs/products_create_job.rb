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

    payload = webhook.is_a?(String) ? JSON.parse(webhook) : webhook

    product_limit = shop.effective_product_limit
    current_count = shop.products.count

    # Free / Starter: hard-cap at plan limit
    unless shop.pro?
      if current_count >= product_limit
        Rails.logger.info("ProductsCreateJob: product limit (#{product_limit}) reached for #{shop_domain} [#{shop.plan_label}] — skipping")
        return
      end
    end

    Shopify::ProductSyncService.new(shop: shop, product_id: payload["id"]).call
    shop.update_column(:products_synced_at, Time.current)

    # Pro: charge overage if count now exceeds limit
    if shop.overage_eligible? && shop.products.count > product_limit
      OverageService.new(shop: shop, resource_type: :product).check_and_charge!
    end
  end
end
