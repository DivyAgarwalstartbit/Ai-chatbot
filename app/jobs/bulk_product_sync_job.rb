class BulkProductSyncJob < ApplicationJob
  queue_as :default

  def perform(shop_id)
    shop = Shop.find(shop_id)

    # Submit bulk operation to Shopify and poll until complete — returns download URL
    url = Shopify::BulkProductSyncService.new(shop).call

    Rails.logger.info "BulkProductSyncJob: starting import from #{url}"

    # Download JSONL and save products/variants/embeddings
    Shopify::BulkProductImportService.new(shop, url).call

    shop.update!(products_synced_at: Time.current)

    product_count = shop.products.count
    ProductSyncMailer.sync_completed(shop: shop, product_count: product_count).deliver_later

  rescue => e
    Rails.logger.error "BulkProductSyncJob failed: #{e.class}: #{e.message}"
    raise
  ensure
    shop&.update!(sync_status: "idle")
  end
end
