module Shopify
  class BulkProductSyncService
    POLL_INTERVAL = 3   # seconds between status checks
    TIMEOUT       = 300 # 5 minutes max wait

    def initialize(shop)
      @shop = shop
    end

    # Submits the bulk operation and polls until complete.
    # Returns the download URL when done.
    def call
      submit_operation
      poll_for_url
    end

    private

    def submit_operation
      response = client.query(query: mutation)

      Rails.logger.info "========== BULK RESPONSE =========="
      Rails.logger.info response.body.inspect

      errors = response.body.dig("data", "bulkOperationRunQuery", "userErrors")

      if errors.present?
        messages = errors.map { |e| e["message"] }.join(", ")
        Rails.logger.error "BULK SYNC userErrors: #{messages}"
        raise "Shopify bulk operation rejected: #{messages}"
      end

      Rails.logger.info "BULK SYNC submitted successfully — polling for completion"
    end

    def poll_for_url
      started = Time.current

      loop do
        result = client.query(query: status_query)
        op     = result.body.dig("data", "currentBulkOperation")
        status = op&.dig("status")

        Rails.logger.info "BULK OPERATION STATUS: #{status}"

        case status
        when "COMPLETED"
          url = op["url"]
          Rails.logger.info "BULK OPERATION COMPLETED — URL: #{url}"
          return url
        when "FAILED", "CANCELED"
          raise "Bulk operation #{status.downcase}"
        when nil
          raise "No active bulk operation found"
        end

        if Time.current - started > TIMEOUT
          raise "Bulk operation timed out after #{TIMEOUT}s"
        end

        sleep POLL_INTERVAL
      end
    end

    def status_query
      <<~GRAPHQL
        {
          currentBulkOperation {
            status
            url
            errorCode
          }
        }
      GRAPHQL
    end

    def client
      session = ShopifyAPI::Auth::Session.new(
        shop:         @shop.shopify_domain,
        access_token: Shopify::TokenService.new(@shop).valid_token
      )

      ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    end

   def mutation
  <<~GRAPHQL
    mutation {
      bulkOperationRunQuery(
        query: """
        {
          products(query: "status:active") {
            edges {
              node {
                id
                title
                handle
                description

                # Product Type
                productType

                # Tags
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

                variants(first: 250) {
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
