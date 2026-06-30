module Shopify
  class CreateAiMetafieldService
    def initialize(shop)
      @shop = shop
    end

    def call
      session = ShopifyAPI::Auth::Session.new(
        shop: @shop.shopify_domain,
        access_token: Shopify::TokenService.new(@shop).valid_token
      )

      client = ShopifyAPI::Clients::Graphql::Admin.new(
        session: session
      )

      mutation = <<~GRAPHQL
        mutation CreateDefinition($definition: MetafieldDefinitionInput!) {
          metafieldDefinitionCreate(definition: $definition) {
            createdDefinition {
              id
              name
              namespace
              key
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL

      client.query(
        query: mutation,
        variables: {
          definition: {
            name: "AI Product Information",
            namespace: "ai_support",
            key: "knowledge",
            ownerType: "PRODUCT",
            type: "multi_line_text_field",
            description: "Information used by the AI assistant to answer customer questions.",
            pin: true
          }
        }
      )
    rescue => e
      Rails.logger.error("Metafield Creation Error: #{e.message}")
    end
  end
end
