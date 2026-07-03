class OrdersLookupController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_cors_headers

  def options
    head :ok
  end

  def lookup
    shop = Shop.find_by(shopify_domain: params[:shop])

    unless shop
      render json: { type: "error", message: "Shop not found." }
      return
    end

    # Find the existing open conversation for this session so we write the
    # active_order to the same Redis key that OutputController reads from.
    conversation = Conversation.find_by(shop: shop, session_id: params[:session_id], status: "open")

    unless conversation
      render json: { type: "error", message: "Session not found. Please refresh and try again." }
      return
    end

    memory = Ai::MemoryService.new(
      shop:       shop,
      customer:   conversation.customer,
      session_id: params[:session_id]
    )

    result = Ai::OrderAgentService.new(
      shop:     shop,
      message:  "order_lookup_submit",
      customer: conversation.customer,
      memory:   memory
    ).call_with_form(params)

    render json: result
  end

  private

 def set_cors_headers
  response.headers["Access-Control-Allow-Origin"] = "*"
  response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
  response.headers["Access-Control-Allow-Headers"] =
    "Content-Type, Authorization, Accept, Origin, X-Requested-With, ngrok-skip-browser-warning"

  response.headers["Access-Control-Max-Age"] = "86400"
end
end
