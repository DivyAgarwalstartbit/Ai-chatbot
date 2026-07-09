# frozen_string_literal: true

class LimitReachedMailer < ApplicationMailer
  RESOURCE_LABELS = {
    conversation: { label: "Conversations",  limit_method: :effective_conversation_limit },
    ticket:       { label: "Support Tickets", limit_method: :effective_ticket_limit },
    document:     { label: "Documents",       limit_method: :effective_document_limit },
    product:      { label: "Products",        limit_method: :effective_product_limit }
  }.freeze

  def limit_reached(shop:, resource:)
    @shop     = shop
    @resource = resource.to_sym
    @label    = RESOURCE_LABELS.dig(@resource, :label) || resource.to_s.humanize
    @limit    = shop.public_send(RESOURCE_LABELS.dig(@resource, :limit_method))
    @pro_price = Shop::PLANS["pro"][:price]
    @upgrade_url = "#{ENV.fetch('HOST', '')}/billing/create?plan=pro&shop=#{shop.shopify_domain}&embedded=0"

    mail(
      to:      merchant_email,
      subject: "⚠️ #{@label} limit reached — upgrade to Pro to continue"
    )
  end

  private

  def merchant_email
    vr = (@shop.ai_shopper_configuration&.visibility_rules || {}).with_indifferent_access
    vr[:support_email].presence || ENV.fetch("SMTP_USERNAME", nil)
  end
end
