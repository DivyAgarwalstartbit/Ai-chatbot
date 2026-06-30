# frozen_string_literal: true

class OutputController < ApplicationController
  include ActionController::Live

  skip_before_action :verify_authenticity_token
  before_action :set_cors_headers

    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { success: false, error: e.message }, status: :not_found
    end

    # StandardError rescue HATA DO — infinite loop ka root cause yahi hai

    def options
      head :ok
    end

    def configuration
      Rails.logger.info "🔥 CONFIG HIT #{params.inspect}"

      shop = Shop.find_by!(shopify_domain: params[:shop])
      cfg  = shop.ai_shopper_configuration || AiShopperConfiguration.new
      ws   = (cfg.widget_settings  || {}).with_indifferent_access
      vr   = (cfg.visibility_rules || {}).with_indifferent_access

      response = {
        widget_enabled:           cfg.widget_enabled != false,
        assistant_name:           cfg.assistant_name.presence || "AI Assistant",
        assistant_avatar_url:     cfg.assistant_avatar_url.presence || "",
        business_logo_url:        ws[:business_logo_url].presence || "",
        greeting:                 cfg.greeting.presence || "Welcome! How can I help you today?",
        starter_prompts:          Array(cfg.starter_prompts).map(&:to_s).reject(&:blank?),
        primary_color:            ws[:primary_color].presence || "#ff6500",
        background_color:         ws[:background_color].presence || "#ffffff",
        text_color:               ws[:text_color].presence || "#1a202c",
        font_family:              ws[:font_family].presence || "Inter",
        desktop_alignment:        ws[:desktop_alignment].presence || "right",
        mobile_alignment:         ws[:mobile_alignment].presence || "right",
        desktop_side_spacing:     ws[:desktop_side_spacing].to_i.nonzero? || 16,
        mobile_side_spacing:      ws[:mobile_side_spacing].to_i.nonzero? || 8,
        desktop_vertical_offset:  ws[:desktop_vertical_offset].to_i.nonzero? || 80,
        mobile_vertical_offset:   ws[:mobile_vertical_offset].to_i.nonzero? || 130,
        widget_icon_url:          ws[:widget_icon_url].presence || "",
        widget_icon_type:         ws[:widget_icon_type].presence || "default",
        enable_animation:         ws[:enable_animation].nil? ? true : ws[:enable_animation].to_s == "true",
        animation_text:           ws[:animation_text].presence || "Hi there! Need help?",
        enable_add_to_cart:       ws[:enable_add_to_cart].nil? ? true : ws[:enable_add_to_cart].to_s == "true",
        enable_related_questions: ws[:enable_related_questions].nil? ? true : ws[:enable_related_questions].to_s == "true",
        related_questions_count:  ws[:related_questions_count].to_i.nonzero? || 3,
        hide_on_mobile:           vr[:hide_on_mobile].to_s   == "1" || vr[:hide_on_mobile]   == true,
        hide_on_desktop:          vr[:hide_on_desktop].to_s  == "1" || vr[:hide_on_desktop]  == true,
        hide_on_checkout:         vr[:hide_on_checkout].to_s == "1" || vr[:hide_on_checkout] == true,
        hide_on_cart:             vr[:hide_on_cart].to_s     == "1" || vr[:hide_on_cart]     == true
      }

      Rails.logger.info "🔥 CONFIG RESPONSE #{response}"

      render json: response
    end

    def history
      shop = Shop.find_by!(shopify_domain: params[:shop])

      conversation = Conversation.find_by(
        shop:       shop,
        session_id: params[:session_id],
        status:     "open"
      )

      unless conversation
        render json: { messages: [] } and return
      end

      msgs = conversation.messages
        .order(created_at: :asc)
        .map { |m| { role: m.role, content: m.content, metadata: m.metadata } }

      render json: { messages: msgs, session_id: conversation.session_id }
    rescue => e
      Rails.logger.error("[History] #{e.class}: #{e.message}")
      render json: { messages: [] }
    end

    def reset
      shop         = Shop.find_by!(shopify_domain: params[:shop])
      conversation = Conversation.find_by(shop: shop, session_id: params[:session_id])

      if conversation
        conversation.update_columns(status: "closed", ended_at: Time.current)

        redis = Redis.new(url: ENV["REDIS_URL"])
        redis.del(
          "ai:ctx:conversation:#{conversation.id}",
          "ai:summary:conversation:#{conversation.id}"
        )
      end

      render json: { success: true, new_session_id: SecureRandom.uuid }
    rescue => e
      Rails.logger.error("[Reset] #{e.class}: #{e.message}")
      render json: { success: false, error: e.message }, status: :internal_server_error
    end

    def stream
      shop     = Shop.find_by!(shopify_domain: params[:shop])
      customer = find_or_create_customer(shop)

      response.headers["Content-Type"]      = "text/event-stream"
      response.headers["Cache-Control"]     = "no-cache"
      response.headers["X-Accel-Buffering"] = "no"

      begin
        ai_response = Ai::ChatService.new(
          shop:       shop,
          customer:   customer,
          session_id: session_id,
          message:    params[:message],
          stream_callback: ->(token) {
            response.stream.write("data: #{token.to_json}\n\n")
          }
        ).call

        response.stream.write("event: done\ndata: #{ai_response.to_json}\n\n")
      rescue ActionController::Live::ClientDisconnected
        # client navigated away — nothing to do
      rescue StandardError => e
        Rails.logger.error("[Stream] #{e.class}: #{e.message}")
        response.stream.write("event: error\ndata: #{e.message.to_json}\n\n")
      ensure
        response.stream.close
      end
    end

    def create
      shop     = Shop.find_by!(shopify_domain: params[:shop])
      customer = find_or_create_customer(shop)

      ai_response = Ai::ChatService.new(
        shop:       shop,
        customer:   customer,
        session_id: session_id,
        message:    params[:message]
      ).call

      active_session_id = ai_response.is_a?(Hash) ? (ai_response[:session_id] || session_id) : session_id

      render json: {
        success:    true,
        session_id: active_session_id,
        response:   ai_response
      }
    rescue => e
      Rails.logger.error "[Chat] #{e.class}: #{e.message}"
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
      customer = Customer.find_or_create_by!(shop: shop, shopify_customer_id: params[:customer_id]) do |c|
        c.email      = params[:email]
        c.first_name = params[:first_name]
      end

      # Upgrade: if the same browser was previously a guest (visitor_id present),
      # re-parent any open guest conversation to this logged-in customer.
      if params[:visitor_id].present? && customer.conversations.none?
        guest = Customer.find_by(shop: shop, visitor_id: params[:visitor_id], shopify_customer_id: nil)
        if guest
          guest.conversations.update_all(customer_id: customer.id)
          customer.update_columns(visitor_id: params[:visitor_id]) if customer.visitor_id.blank?
        end
      end

      customer
    end

    def set_cors_headers
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
      response.headers["Access-Control-Allow-Headers"] =
        "Content-Type, ngrok-skip-browser-warning"
    end
end
