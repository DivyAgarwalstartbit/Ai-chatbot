module Api
  class ConversationsController < ApplicationController
    skip_before_action :verify_authenticity_token
    before_action :set_cors_headers

    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { success: false, error: e.message }, status: :not_found
    end

    rescue_from StandardError do |e|
      render json: { success: false, error: e.message }, status: :internal_server_error
    end

    def options
      head :ok
    end

    def create
      shop = Shop.find_by!(shopify_domain: params[:shop])
      customer = find_or_create_customer(shop)

      ai_response = Ai::ChatService.new(
        shop: shop,
        customer: customer,
        session_id: session_id,
        message: params[:message]
      ).call

      render json: {
        success: true,
        session_id: session_id,
        response: ai_response
      }
    end

    private

    def session_id
      @session_id ||= params[:session_id].presence || SecureRandom.uuid
    end

    def find_or_create_customer(shop)
      return logged_customer(shop) if params[:customer_id].present?

      Customer.find_or_create_by!(
        shop: shop,
        visitor_id: params[:visitor_id]
      ) do |c|
        c.first_name = "Guest"
      end
    end

    def logged_customer(shop)
      Customer.find_or_create_by!(
        shop: shop,
        shopify_customer_id: params[:customer_id]
      ) do |c|
        c.email = params[:email]
        c.first_name = params[:first_name]
      end
    end

    def set_cors_headers
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS"
      response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    end
  end
end
