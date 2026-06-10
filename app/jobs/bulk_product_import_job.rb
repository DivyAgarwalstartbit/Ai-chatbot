class BulkProductImportJob < ApplicationJob
  queue_as :default


  def perform(shop_id)
    shop = Shop.find(shop_id)

    Rails.logger.info "======================"
    Rails.logger.info "IMPORT JOB STARTED"
    Rails.logger.info shop_id
    Rails.logger.info "======================"

    Shopify::BulkProductImportService
      .new(shop)
      .call

    shop.update!(sync_status: "idle")
  end
end
