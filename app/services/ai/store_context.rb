# frozen_string_literal: true

module Ai
  # Builds a reusable store-identity context string from the shop's
  # AiShopperConfiguration. Injected into every LLM system prompt so the
  # model knows what brand it is representing, what it sells, and how to
  # direct customers for support.
  module StoreContext
    def self.for(shop)
      return "" if shop.nil?

      cfg = shop.ai_shopper_configuration
      return "" if cfg.nil?

      sd = (cfg.store_details     || {}).with_indifferent_access
      vr = (cfg.visibility_rules  || {}).with_indifferent_access

      brand_name    = sd[:brand_name].presence
      raw_category  = sd[:brand_category].to_s
      category      = raw_category == "custom" ? sd[:custom_brand_category].presence : raw_category.presence
      description   = sd[:brand_description].presence
      support_email = vr[:support_email].presence
      support_phone = vr[:whatsapp].presence

      lines = []
      lines << "Store name: #{brand_name}"                     if brand_name
      lines << "Store category / niche: #{category}"           if category
      lines << "About the store: #{description}"               if description
      lines << "Support email: #{support_email}"               if support_email
      lines << "Support phone / WhatsApp: #{support_phone}"    if support_phone

      return "" if lines.empty?

      lines.join("\n")
    end
  end
end
