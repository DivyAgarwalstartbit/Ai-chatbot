module Shopify
  class ProductSyncService
    def initialize(shop:, product_id:)
      @shop = shop
      @product_id = product_id
    end

    def call
      response = client.query(
        query: query,
        variables: {
          id: "gid://shopify/Product/#{@product_id}"
        }
      )

      product = response.body.dig("data", "product")

      raise "Product #{@product_id} not found" unless product

      ProductImportService.new(@shop).call(product)
    end

    private

    def client
      session = ShopifyAPI::Auth::Session.new(
        shop: @shop.shopify_domain,
        access_token: Shopify::TokenService.new(@shop).valid_token
      )

      ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    end

    def query
      <<~GRAPHQL
        query Product($id: ID!) {
          product(id: $id) {
            id
            title
            handle
            description
            productType
            tags

            metafield(namespace: "ai_support", key: "knowledge") {
              value
            }

            featuredMedia {
              ... on MediaImage {
                image {
                  url
                }
              }
            }

            collections(first: 20) {
              edges {
                node {
                  id
                  title
                  handle
                }
              }
            }

            variants(first: 100) {
              edges {
                node {
                  id
                  title
                  sku
                  price
                  compareAtPrice
                  inventoryQuantity

                  selectedOptions {
                    name
                    value
                  }
                }
              }
            }
          }
        }
      GRAPHQL
    end
  end
end
