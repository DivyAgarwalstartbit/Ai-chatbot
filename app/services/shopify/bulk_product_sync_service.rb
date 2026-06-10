module Shopify
  class BulkProductSyncService
    def initialize(shop)
      @shop = shop
    end



    def call
      response =
        client.query(
          query: mutation
        )


      Rails.logger.info "========== BULK RESPONSE =========="

      Rails.logger.info(
        response.body.inspect
      )


      errors =
        response.body.dig(
          "data",
          "bulkOperationRunQuery",
          "userErrors"
        )


      if errors.present?

        Rails.logger.error(
          errors
        )

      end
    end






    private



    def client
      session =
        ShopifyAPI::Auth::Session.new(
          shop: @shop.shopify_domain,
         access_token:
            Shopify::TokenService
            .new(@shop)
            .valid_token
        )


      ShopifyAPI::Clients::Graphql::Admin.new(
        session: session
      )
    end






    def mutation
      <<~GRAPHQL

      mutation {

        bulkOperationRunQuery(

          query: """

          {
  products {
    edges {
      node {

        id
        title
        handle
        description

        featuredMedia {
          ... on MediaImage {
            image {
              url
            }
          }
        }


        variants {
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
  }
}

          """

        ) {


          bulkOperation {


            id


            status


          }



          userErrors {


            field


            message


          }


        }


      }

      GRAPHQL
    end
  end
end
