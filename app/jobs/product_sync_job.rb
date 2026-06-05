class ProductSyncJob < ApplicationJob
queue_as :default


def perform(shop_id)
 shop =
 Shop.find(shop_id)


 Shopify::ProductSyncService
 .new(shop)
 .call
end
end
