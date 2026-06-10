class BulkOperationsFinishJob < ActiveJob::Base
  extend ShopifyAPI::Webhooks::WebhookHandler



  def self.handle(webhook)
    data = webhook[:data]


    perform_later(
      shop_domain: data.shop,
      webhook: data.body
    )
  end





  def perform(
    shop_domain:,
    webhook:
  )
    Rails.logger.info(
      "========== BULK FINISH RECEIVED =========="
    )


    Rails.logger.info(
      webhook.inspect
    )



    shop =
      Shop.find_by(
        shopify_domain: shop_domain
      )


    unless shop

      Rails.logger.error(
        "SHOP NOT FOUND #{shop_domain}"
      )

      return

    end


    BulkProductImportJob.perform_later(
      shop.id
    )
  end
end
