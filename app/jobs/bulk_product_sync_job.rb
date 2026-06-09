class BulkProductSyncJob < ApplicationJob
  queue_as :default



  def perform(shop_id)
    shop = Shop.find(shop_id)


    Shopify::BulkProductSyncService
      .new(shop)
      .call
  end
end
