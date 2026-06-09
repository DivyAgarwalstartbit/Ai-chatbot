module Api
class ChatController < ApplicationController
skip_before_action :verify_authenticity_token



def create
shop =
Shop.find_by!(
 shopify_domain: params[:shop]
)



customer =
find_or_create_customer(shop)



response =
Ai::ChatService
.new(

 shop: shop,

 customer: customer,

 session_id: session_id,

 message: params[:message]

)
.call




render json: {
 success: true,
 session_id: session_id,
 response: response
}
end







private







def session_id
params[:session_id].presence ||
SecureRandom.uuid
end








def find_or_create_customer(shop)
return logged_customer(shop) if params[:customer_id].present?




Customer.find_or_create_by!(

 shop: shop,


 visitor_id:
 params[:visitor_id]

) do |customer|
 customer.first_name =
 "Guest"
end
end







def logged_customer(shop)
Customer.find_or_create_by!(

 shop: shop,

 shopify_customer_id:
 params[:customer_id]

) do |customer|
 customer.email =
 params[:email]


 customer.first_name =
 params[:first_name]
end
end
end
end
