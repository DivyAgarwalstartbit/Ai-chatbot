# frozen_string_literal: true

class TicketNotificationMailer < ApplicationMailer
  def new_ticket(ticket:, shop:)
    @ticket       = ticket
    @shop         = shop
    @customer     = ticket.customer
    @support_email = support_email_for(shop)

    mail(
      to:      @support_email,
      subject: "[New Ticket ##{ticket.id}] #{ticket.subject}"
    )
  end

  private

  def support_email_for(shop)
    vr = (shop.ai_shopper_configuration&.visibility_rules || {}).with_indifferent_access
    vr[:support_email].presence || ENV.fetch("SMTP_USERNAME", nil)
  end
end
