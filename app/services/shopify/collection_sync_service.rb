module Shopify
  # Fetches all collections via GraphQL and updates collections_data on matching products.
  # Used after bulk import since Shopify's bulk operation only allows one nested connection.
  class CollectionSyncService
    def initialize(shop)
      @shop = shop
    end

    def call
      cursor = nil
      loop do
        result = fetch_page(cursor)
        collections = result.dig("data", "collections", "edges") || []
        break if collections.empty?

        collections.each { |edge| update_products_for(edge["node"]) }

        page_info = result.dig("data", "collections", "pageInfo")
        break unless page_info&.dig("hasNextPage")
        cursor = collections.last["cursor"]
      end
    rescue => e
      Rails.logger.error("[CollectionSyncService] #{e.class}: #{e.message}")
    end

    private

    def update_products_for(collection)
      title  = collection["title"]
      handle = collection["handle"]
      cid    = collection["id"].split("/").last

      product_gids = collection.dig("products", "edges")&.map { |e| e.dig("node", "id") } || []
      return if product_gids.empty?

      shopify_ids = product_gids.map { |gid| gid.split("/").last }

      products = Product.where(shop_id: @shop.id, shopify_product_id: shopify_ids)
      products.find_each do |product|
        existing = Array(product.collections_data)
        next if existing.any? { |c| c["id"] == cid }
        product.update_column(:collections_data, existing + [{ "id" => cid, "title" => title, "handle" => handle }])
      end
    end

    def fetch_page(cursor)
      after = cursor ? %(after: "#{cursor}",) : ""
      query = <<~GRAPHQL
        {
          collections(first: 50, #{after} sortKey: TITLE) {
            pageInfo { hasNextPage }
            edges {
              cursor
              node {
                id
                title
                handle
                products(first: 250) {
                  edges {
                    node { id }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      client.query(query: query).body
    end

    def client
      session = ShopifyAPI::Auth::Session.new(
        shop:         @shop.shopify_domain,
        access_token: Shopify::TokenService.new(@shop).valid_token
      )
      ShopifyAPI::Clients::Graphql::Admin.new(session: session)
    end
  end
end