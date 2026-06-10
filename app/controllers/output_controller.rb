# frozen_string_literal: true

class OutputController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :set_cors_headers

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { success: false, error: e.message }, status: :not_found
  end

  def options
    head :ok
  end

  def config
    shop = Shop.find_by!(shopify_domain: params[:shop])
    cfg  = shop.ai_shopper_configuration || AiShopperConfiguration.new
    ws   = (cfg.widget_settings || {}).with_indifferent_access

    render json: {
      widget_enabled:          cfg.widget_enabled != false,
      assistant_name:          cfg.assistant_name.presence || "AI Assistant",
      assistant_avatar_url:    cfg.assistant_avatar_url.presence || "",
      business_logo_url:       ws[:business_logo_url].presence || "",
      greeting:                cfg.greeting.presence || "Hi there! 👋 How can I help you today?",
      starter_prompts:         Array(cfg.starter_prompts).map(&:to_s).reject(&:blank?),
      primary_color:           ws[:primary_color].presence || "#ff6500",
      background_color:        ws[:background_color].presence || "#ffffff",
      text_color:              ws[:text_color].presence || "#1a202c",
      font_family:             ws[:font_family].presence || "Inter",
      desktop_alignment:       ws[:desktop_alignment].presence || "right",
      mobile_alignment:        ws[:mobile_alignment].presence || "right",
      desktop_side_spacing:    ws[:desktop_side_spacing].to_i.nonzero? || 16,
      mobile_side_spacing:     ws[:mobile_side_spacing].to_i.nonzero? || 8,
      desktop_vertical_offset: ws[:desktop_vertical_offset].to_i.nonzero? || 80,
      mobile_vertical_offset:  ws[:mobile_vertical_offset].to_i.nonzero? || 130
    }
  rescue => e
    Rails.logger.error "[Output::Config] #{e.class}: #{e.message}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  def create
    shop     = Shop.find_by!(shopify_domain: params[:shop])
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
  rescue => e
    Rails.logger.error "[Output::Chat] #{e.class}: #{e.message}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  private

  def session_id
    @session_id ||= params[:session_id].presence || SecureRandom.uuid
  end

  def find_or_create_customer(shop)
    return logged_customer(shop) if params[:customer_id].present?

    Customer.find_or_create_by!(shop: shop, visitor_id: params[:visitor_id]) do |c|
      c.first_name = "Guest"
    end
  end

  def logged_customer(shop)
    Customer.find_or_create_by!(shop: shop, shopify_customer_id: params[:customer_id]) do |c|
      c.email      = params[:email]
      c.first_name = params[:first_name]
    end
  end

  def set_cors_headers
    response.headers["Access-Control-Allow-Origin"]  = "*"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
  end
end
