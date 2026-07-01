# frozen_string_literal: true

class TicketReplyMailer < ApplicationMailer
  def agent_reply(ticket:, message:, shop:)
    @ticket   = ticket
    @message  = message
    @shop     = shop
    @customer = ticket.customer

    vr             = (shop.ai_shopper_configuration&.visibility_rules || {}).with_indifferent_access
    merchant_email = vr[:support_email].presence

    options = {
      to:      @customer.email,
      subject: "Re: #{ticket.subject} [Ticket ##{ticket.id}]"
    }
    options[:reply_to] = merchant_email if merchant_email.present?

    mail(options)
  end
end
