module Ai
  class OrderAgentService
    def initialize(shop:, message:, customer: nil, memory:)
      @shop     = shop
      @message  = message
      @customer = customer
      @memory   = memory
    end

    def call
      # User explicitly wants to check a different order — reset context
      if requesting_new_order?
        @memory.clear_active_order
        return order_lookup_form("Please enter your order details to continue.")
      end

      # Active order already in memory — answer the specific question from it.
      # This check MUST come before extract_order_number so that numbers appearing
      # in a follow-up message ("3 items", "2024") don't re-trigger the form.
      if @memory.active_order.present?
        return answer_from_active_order(@memory.active_order)
      end

      # Fresh context: user mentioned an order number → require form verification
      order_number = extract_order_number
      if order_number.present?
        return order_lookup_form("Please confirm your order details.", prefill_order_number: order_number)
      end

      # No active order, no order number → show blank form
      order_lookup_form("Please enter your order details to continue.")
    end

    def call_with_form(params)
      order_number = params[:order_id].to_s.delete("#").strip
      email        = params[:email].to_s.strip
      phone        = params[:phone].to_s.strip

      if order_number.blank?
        return order_lookup_form("Please enter your order number.")
      end

      order = fetch_order_from_shopify(order_number)

      return order_lookup_form("We couldn't find order ##{order_number}. Please check and try again.") unless order

      email_match = email.blank? || order["email"].to_s.downcase == email.downcase
      phone_match = phone.blank? || order["phone"].to_s.gsub(/\D/, "") == phone.gsub(/\D/, "")

      unless email_match || phone_match
        return order_lookup_form("The email or phone number doesn't match our records for that order.")
      end

      @memory.set_active_order(order)
      format_order_response(order)
    end

    private

    NEW_ORDER_PATTERNS = [
      "another order",
      "different order",
      "other order",
      "new order",
      "second order",
      "check another order",
      "track another order",
      "track another package",
      "my other order",
      "one more order",
      "another package",
      "different package"
    ].freeze

    def requesting_new_order?
      msg = @message.to_s.downcase.strip
      NEW_ORDER_PATTERNS.any? { |pattern| msg.include?(pattern) }
    end

    def extract_order_number
      match = @message.match(/#?\d{3,}/)
      match&.to_s&.delete("#")
    end

    # ----------------------------
    # Answer a follow-up question using the active order in memory
    # ----------------------------
    def answer_from_active_order(order)
      context = build_order_context(order)

      message = Ai::ChatGenerationService.new(
        message:      @message,
        context:      context,
        shop:         @shop,
        instructions: <<~TEXT
          The customer is asking a follow-up question about their order. Answer ONLY from the order data above.
          - Be specific and direct — answer exactly what they asked.
          - Include tracking info if available and the question is about shipping/delivery.
          - Keep it to 2-3 sentences.
          - Do NOT ask for order number or email — you already have the order on file.
          - Do NOT invent information not present in the data.
        TEXT
      ).call

      # Return plain text — the order card was already shown on the first lookup.
      # Re-rendering it on every follow-up clutters the conversation.
      { type: "text", message: message }
    end

    def build_order_context(order)
      items = Array(order.dig("lineItems", "edges")).map do |e|
        node = e["node"]
        "#{node["title"]} x#{node["quantity"]}"
      end.join(", ")

      tracking = Array(order["fulfillments"]).flat_map { |f| Array(f["trackingInfo"]) }
        .map { |t| "#{t["company"]}: #{t["number"]} (#{t["url"]})" }.join("; ")

      total    = order.dig("currentTotalPriceSet", "shopMoney", "amount")
      currency = order.dig("currentTotalPriceSet", "shopMoney", "currencyCode")

      <<~TEXT
        Order: #{order["name"]}
        Placed: #{order["createdAt"]}
        Payment status: #{order["displayFinancialStatus"]}
        Fulfillment status: #{order["displayFulfillmentStatus"]}
        Items: #{items.presence || "N/A"}
        Total: #{total} #{currency}
        Tracking: #{tracking.presence || "Not yet available"}
        Shipping to: #{order.dig("shippingAddress", "city")}, #{order.dig("shippingAddress", "country")}
      TEXT
    end

    # ----------------------------
    # UI response: form
    # ----------------------------
    def order_lookup_form(message, prefill_order_number: nil)
      {
        type:    "order_lookup_form",
        message: message,
        form:    {
          order_id: prefill_order_number,
          fields:   [
            { name: "order_id", type: "text",  label: "Order ID" },
            { name: "email",    type: "email", label: "Email Address" },
            { name: "phone",    type: "text",  label: "Phone Number" }
          ]
        }
      }
    end

    # ----------------------------
    # Shopify lookup (GraphQL)
    # ----------------------------
    def fetch_order_from_shopify(order_number)
      Rails.logger.info "Fetching order ##{order_number} from Shopify for shop #{@shop.shopify_domain}"
      session = ShopifyAPI::Auth::Session.new(
        shop:         @shop.shopify_domain,
        access_token: Shopify::TokenService.new(@shop).valid_token
      )
      client = ShopifyAPI::Clients::Graphql::Admin.new(session: session)

      query = <<~GRAPHQL
        query($search_query: String!) {
          orders(first: 1, query: $search_query) {
            edges {
              node {
                id
                name
                createdAt
                email
                phone
                displayFinancialStatus
                displayFulfillmentStatus
                returns(first: 1) {
                  edges {
                    node {
                      status
                    }
                  }
                }
                currentSubtotalPriceSet {
                  shopMoney { amount currencyCode }
                }
                currentShippingPriceSet {
                  shopMoney { amount currencyCode }
                }
                currentTaxLines {
                  title
                  rate
                  priceSet {
                    shopMoney { amount }
                  }
                }
                currentTotalPriceSet {
                  shopMoney { amount currencyCode }
                }
                shippingAddress {
                  name company address1 address2 city province zip country phone
                }
                fulfillments {
                  status
                  trackingInfo { company number url }
                }
                lineItems(first: 50) {
                  edges {
                    node {
                      title
                      quantity
                      originalUnitPriceSet {
                        shopMoney { amount currencyCode }
                      }
                      originalTotalSet {
                        shopMoney { amount }
                      }
                      variant {
                        sku
                        image { url }
                        product { featuredImage { url } }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      GRAPHQL

      response = client.query(
        query:     query,
        variables: { search_query: "name:##{order_number}" }
      )

      body = response.body
      Rails.logger.info "Shopify Order Lookup Response: #{body.inspect}"

      if body["errors"].present?
        Rails.logger.error "Shopify Order GraphQL errors: #{body["errors"].inspect}"
        return nil
      end

      body.dig("data", "orders", "edges", 0, "node")
    rescue => e
      Rails.logger.error "Shopify Order Fetch Error: #{e.class}: #{e.message}"
      nil
    end

    # ----------------------------
    # Format final order card payload
    # ----------------------------
    def format_order_response(order)
      {
        type:    "order_details",
        message: "Here are your order details:",
        order:   {
          id:                 order["id"],
          name:               order["name"],
          created_at:         order["createdAt"],
          financial_status:   order["displayFinancialStatus"],
          fulfillment_status: order["displayFulfillmentStatus"],

          subtotal: order.dig("currentSubtotalPriceSet", "shopMoney", "amount"),
          shipping: order.dig("currentShippingPriceSet", "shopMoney", "amount"),
          total:    order.dig("currentTotalPriceSet",    "shopMoney", "amount"),
          currency: order.dig("currentTotalPriceSet",    "shopMoney", "currencyCode"),

          tax: order["currentTaxLines"]&.sum { |t| t.dig("priceSet", "shopMoney", "amount").to_f } || 0,

          shipping_address: {
            name:     order.dig("shippingAddress", "name"),
            company:  order.dig("shippingAddress", "company"),
            address1: order.dig("shippingAddress", "address1"),
            address2: order.dig("shippingAddress", "address2"),
            city:     order.dig("shippingAddress", "city"),
            province: order.dig("shippingAddress", "province"),
            zip:      order.dig("shippingAddress", "zip"),
            country:  order.dig("shippingAddress", "country"),
            phone:    order.dig("shippingAddress", "phone")
          },

          items: order.dig("lineItems", "edges")&.map do |edge|
            item = edge["node"]
            {
              title:       item["title"],
              quantity:    item["quantity"],
              sku:         item.dig("variant", "sku"),
              image:       item.dig("variant", "image", "url") ||
                           item.dig("variant", "product", "featuredImage", "url"),
              unit_price:  item.dig("originalUnitPriceSet", "shopMoney", "amount"),
              total_price: item.dig("originalTotalSet", "shopMoney", "amount")
            }
          end || [],

          tracking: order["fulfillments"]&.flat_map { |f| f["trackingInfo"] || [] } || []
        }
      }
    end
  end
end
