require "open-uri"
require "json"


module Shopify
class BulkProductImportService
def initialize(shop)
 @shop = shop
end




def call
 url = bulk_file_url


 return unless url



 product_map = {}


 URI.open(url) do |file|
  file.each_line do |line|
   data = JSON.parse(line)



   if product?(data)


    product =
     save_product(data)


    product_map[
      data["id"]
    ] = product.id



   elsif variant?(data)


    save_variant(
     data,
     product_map
    )


   end
  end
 end

 product_map.values.each do |product_id|
  ProductEmbeddingJob.perform_later(
    product_id
  )
 end
end


private


def product?(data)
 data["id"]
 .include?(
  "Product/"
 )
end


def variant?(data)
 data["id"]
 .include?(
  "ProductVariant/"
 )
end



def save_product(data)
 Product.find_or_initialize_by(

  shop_id: @shop.id,


  shopify_product_id:
   shopify_id(
    data["id"]
   )


 ).tap do |product|
  product.title =
   data["title"]



  product.description =
   data["description"]



  product.handle =
   data["handle"]




  product.image_url =
   data.dig(
    "featuredMedia",
    "image",
    "url"
   )



  product.save!
 end
end


def save_variant(data, product_map)
 product_gid =
  data["__parentId"]



 product_id =
  product_map[
   product_gid
  ]


 return unless product_id

 ProductVariant
 .find_or_initialize_by(

  shop_id: @shop.id,


  shopify_variant_id:
   shopify_id(
    data["id"]
   )


 ).tap do |variant|
  variant.product_id =
   product_id

  variant.title =
   data["title"]

  variant.sku =
   data["sku"]

  variant.price =
   data["price"]

  variant.compare_at_price =
   data["compareAtPrice"]

  variant.inventory_quantity =
   data["inventoryQuantity"]

  variant.available =
   data["inventoryQuantity"].to_i > 0

  variant.options =
   data["selectedOptions"]


  variant.save!
 end
end



def shopify_id(gid)
 gid.split("/")
    .last
end


def bulk_file_url
 response =
  client.query(

   query:
    <<~GRAPHQL

    {

     currentBulkOperation {

      status

      url

     }

    }

    GRAPHQL

  )



 response.body.dig(

  "data",

  "currentBulkOperation",

  "url"

 )
end







def client
 session =
  ShopifyAPI::Auth::Session.new(


   shop:
    @shop.shopify_domain,



   access_token:
    Shopify::TokenService
    .new(@shop)
    .valid_token


  )




 ShopifyAPI::Clients::Graphql::Admin.new(

  session: session

 )
end
end
end
