class BulkProductImportJob < ApplicationJob
  queue_as :default


  def perform(shop_id, url)
    shop = Shop.find(shop_id)

    Rails.logger.info "======================"
    Rails.logger.info "IMPORT JOB STARTED"
    Rails.logger.info "shop_id=#{shop_id} url=#{url}"
    Rails.logger.info "======================"

    Shopify::BulkProductImportService
      .new(shop, url)
      .call

  rescue => e
    Rails.logger.error "BulkProductImportJob failed: #{e.class}: #{e.message}"
  ensure
    shop&.update!(sync_status: "idle")
  end
end
