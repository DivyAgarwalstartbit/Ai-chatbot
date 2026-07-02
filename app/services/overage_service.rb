# frozen_string_literal: true

# Charges a $0.30 overage bundle to a Pro merchant via Shopify's usage billing API,
# then increments the shop's extra quota columns.
#
# Usage:
#   result = OverageService.new(shop: shop, resource_type: :conversation).check_and_charge!
#   result[:success] => true / false
#   result[:reason]  => nil / "not_pro" / "no_usage_sub" / "shopify_error" / "exception"
class OverageService
  USAGE_MUTATION = <<~GQL.freeze
    mutation AppUsageRecordCreate($subscriptionLineItemId: ID!, $price: MoneyInput!, $description: String!) {
      appUsageRecordCreate(subscriptionLineItemId: $subscriptionLineItemId, price: $price, description: $description) {
        userErrors { field message }
        appUsageRecord { id }
      }
    }
  GQL

  def initialize(shop:, resource_type:)
    @shop          = shop
    @resource_type = resource_type.to_sym
  end

  def check_and_charge!
    return { success: false, reason: "not_pro" }      unless @shop.pro?
    return { success: false, reason: "no_usage_sub" } unless @shop.usage_subscription_id.present?

    ShopOverageBundle.transaction do
      # Lock the shop row to prevent concurrent double-charges
      shop   = Shop.lock.find(@shop.id)
      result = call_shopify(shop)
      return result unless result[:success]

      shop.increment!(:extra_conversations,            Shop::OVERAGE_BUNDLE[:conversations])
      shop.increment!(:extra_tickets,                  Shop::OVERAGE_BUNDLE[:tickets])
      shop.increment!(:extra_documents,                Shop::OVERAGE_BUNDLE[:documents])
      shop.increment!(:extra_products,                 Shop::OVERAGE_BUNDLE[:products])
      shop.increment!(:extra_messages_per_conversation, Shop::OVERAGE_BUNDLE[:messages_per_conversation])

      ShopOverageBundle.create!(
        shop:                    shop,
        resource_type:           @resource_type.to_s,
        amount:                  Shop::OVERAGE_BUNDLE_PRICE.to_d,
        shopify_usage_record_id: result[:usage_record_id],
        charged_at:              Time.current
      )

      { success: true }
    end
  rescue => e
    Rails.logger.error("[OverageService] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    { success: false, reason: "exception" }
  end

  private

  def call_shopify(shop)
    session = ShopifyAPI::Auth::Session.new(
      shop:         shop.shopify_domain,
      access_token: shop.shopify_token
    )
    client   = ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    response = client.query(query: USAGE_MUTATION, variables: {
      subscriptionLineItemId: shop.usage_subscription_id,
      price:                  { amount: Shop::OVERAGE_BUNDLE_PRICE, currencyCode: "USD" },
      description:            "Overage bundle: +#{Shop::OVERAGE_BUNDLE[:conversations]} conversations, " \
                              "+#{Shop::OVERAGE_BUNDLE[:messages_per_conversation]} messages/conversation, " \
                              "+#{Shop::OVERAGE_BUNDLE[:tickets]} tickets, " \
                              "+#{Shop::OVERAGE_BUNDLE[:documents]} documents, " \
                              "+#{Shop::OVERAGE_BUNDLE[:products]} products ($#{Shop::OVERAGE_BUNDLE_PRICE})"
    })

    errors = response.body.dig("data", "appUsageRecordCreate", "userErrors")
    if errors&.any?
      Rails.logger.error("[OverageService] Shopify userErrors: #{errors.inspect}")
      return { success: false, reason: "shopify_error", errors: errors }
    end

    usage_record_id = response.body.dig("data", "appUsageRecordCreate", "appUsageRecord", "id")
    { success: true, usage_record_id: usage_record_id }
  end
end
