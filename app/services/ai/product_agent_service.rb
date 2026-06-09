module Ai
class ProductAgentService
def initialize(
 shop:,
 message:,
 intent:,
 memory:
)
 @shop = shop
 @message = message
 @intent = intent
 @memory = memory
end





def call
return recommendation_response if recommendation?



products =
 Ai::ProductSearchService
 .new(
  shop: @shop,
  query: @message
 )
 .call



return not_found_response if products.empty?



if products.all? { |p| out_of_stock?(p) }

 return out_of_stock_response(
  products.first
 )

end



product_answer(products)
end








private





# =====================
# Checks
# =====================


def recommendation?
 @intent == "product_recommendation"
end





def out_of_stock?(product)
product
.product_variants
.none? do |variant|
 variant.inventory_quantity.to_i > 0
end
end









# =====================
# CASE A
# Product Found
# =====================


def product_answer(products)
product =
 products.first



save_product_context(product)



context =
products.map do |p|
variants =
p.product_variants.map do |v|
stock =
v.inventory_quantity.to_i



availability =
stock.positive? ?
"AVAILABLE" :
"OUT_OF_STOCK"




<<~TEXT

Variant:
#{v.title}

Price:
#{v.price}

Inventory:
#{stock}

Availability:
#{availability}

TEXT
end.join("\n")




<<~TEXT

Product:
#{p.title}

Description:
#{p.description}

#{variants}

TEXT
end.join("\n")







Ai::ChatGenerationService
.new(

 message: @message,


 context:
<<~TEXT

Previous conversation:

#{@memory.context}


Product data:

#{context}
,


 instructions:


You are ecommerce product assistant.

Rules:

- Use only product data.
- Never invent products.
- Use Availability field.
- AVAILABLE means in stock.
- OUT_OF_STOCK means unavailable.
- Mention matching variant if asked.
- Keep answer short.

TEXT

)
.call
end











# =====================
# CASE B
# Out of stock
# =====================


def out_of_stock_response(product)
save_product_context(product)



suggestions =
Ai::ProductRecommendationService
.new(
 shop: @shop,
 product: product
)
.call




{
 type: "product_cards",

 message:
 "#{product.title} is currently out of stock. Here are similar products:",


 products:
 build_cards(suggestions)

}
end










# =====================
# CASE C
# Not Found
# =====================


def not_found_response
suggestions =
Ai::ProductRecommendationService
.new(
 shop: @shop,
 query: @message
)
.call




{
 type: "product_cards",


 message:
 "I couldn't find this product. You may like these:",


 products:
 build_cards(suggestions)

}
end










# =====================
# CASE D
# Recommendation
# =====================


def recommendation_response
products =
Ai::ProductRecommendationService
.new(
 shop: @shop,
 query: @message
)
.call



save_product_context(
 products.first
) if products.present?




{
 type: "product_cards",


 message:
 "Here are some products I recommend:",


 products:
 build_cards(products)

}
end










# =====================
# Helpers
# =====================



def save_product_context(product)
return unless product



@memory.set_context(
 "last_product_id",
 product.id
)


@memory.set_context(
 "last_product_title",
 product.title
)
end







def build_cards(products)
products.map do |p|
available_variants =
p.product_variants.select do |v|
 v.inventory_quantity.to_i > 0
end




{

 id: p.id,


 title: p.title,


 image: p.image_url,


 handle: p.handle,


 variants:

 available_variants.map do |v|
 {
  title: v.title,
  price: v.price,
  stock: v.inventory_quantity
 }
 end

}
end
end
end
end
