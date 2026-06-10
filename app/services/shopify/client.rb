module Shopify
  class Client
    def initialize(shop)
      @shop = shop
    end



    def graphql
      session =
        ShopifyAPI::Auth::Session.new(

          shop: @shop.shopify_domain,

          access_token: @shop.shopify_token

        )


      ShopifyAPI::Clients::Graphql::Admin.new(
        session: session
      )
    end
  end
end
