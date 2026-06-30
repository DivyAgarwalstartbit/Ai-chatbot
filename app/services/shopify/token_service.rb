require "net/http"
require "json"


module Shopify
class TokenService
def initialize(shop)
 @shop = shop
end



def valid_token
 return @shop.shopify_token if token_valid?


 refresh_token
end





private



def token_valid?
 @shop.expires_at.present? &&
 @shop.expires_at > 5.minutes.from_now
end


def refresh_token
uri =
URI(
 "https://#{@shop.shopify_domain}/admin/oauth/access_token"
)



response =
Net::HTTP.post(

 uri,

 {
  client_id: ENV["SHOPIFY_API_KEY"],

  client_secret: ENV["SHOPIFY_API_SECRET"],

  grant_type: "refresh_token",

  refresh_token: @shop.refresh_token

 }.to_json,


 "Content-Type" => "application/json"

)

data =
JSON.parse(response.body)


if data["error"]

 raise data.inspect

end

@shop.update!(

 shopify_token:
  data["access_token"],


 refresh_token:
  data["refresh_token"],


 expires_at:
  Time.current + data["expires_in"].seconds

)



data["access_token"]
end
end
end
