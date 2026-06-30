class CreateAiMetafieldJob < ApplicationJob
  queue_as :default

  def perform(shop_id)
    shop = Shop.find_by(id: shop_id)

    unless shop
      Rails.logger.error("CreateAiMetafieldJob: Shop with ID #{shop_id} not found")
      return
    end

    Shopify::CreateAiMetafieldService.new(shop).call

    Rails.logger.info("CreateAiMetafieldJob: AI metafield definition created for #{shop.shopify_domain}")
  rescue => e
    Rails.logger.error("CreateAiMetafieldJob Error: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end
end
