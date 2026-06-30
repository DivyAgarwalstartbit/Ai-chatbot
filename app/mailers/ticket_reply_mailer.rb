# frozen_string_literal: true

class TicketReplyMailer < ApplicationMailer
  def agent_reply(ticket:, message:, shop:)
    @ticket   = ticket
    @message  = message
    @shop     = shop
    @customer = ticket.customer

    # Use env-configured from-address; fall back to a sensible default
    from_addr = ENV.fetch("SUPPORT_EMAIL_FROM", "support@#{shop.shopify_domain}")

    mail(
      to:      @customer.email,
      from:    from_addr,
      subject: "Re: #{ticket.subject} [Ticket ##{ticket.id}]"
    )
  end
end
