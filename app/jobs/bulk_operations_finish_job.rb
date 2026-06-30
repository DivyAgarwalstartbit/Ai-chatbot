class BulkOperationsFinishJob < ActiveJob::Base
  extend ShopifyAPI::Webhooks::WebhookHandler

  def self.handle(topic:, shop:, body:, webhook_id:, api_version:)
    perform_later(shop_domain: shop, webhook: body)
  end

  def perform(shop_domain:, webhook:)
    Rails.logger.info "========== BULK FINISH RECEIVED =========="
    Rails.logger.info webhook.inspect

    shop = Shop.find_by(shopify_domain: shop_domain)

    unless shop
      Rails.logger.error "BULK FINISH: shop not found #{shop_domain}"
      return
    end

    url = webhook["url"] || webhook[:url]

    unless url.present?
      Rails.logger.error "BULK FINISH: no download URL in webhook body — aborting"
      shop.update!(sync_status: "idle")
      return
    end

    Rails.logger.info "BULK FILE URL: #{url}"

    BulkProductImportJob.perform_later(shop.id, url)
  end
end
