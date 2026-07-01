module Ai
  class HumanEscalationService
    def initialize(shop:, customer: nil, message:, memory:)
      @shop     = shop
      @customer = customer
      @message  = message.to_s.strip
      @memory   = memory
    end

    def call
      conversation = @memory.conversation

      ticket = Ticket.create!(
        shop:         @shop,
        customer:     @customer,
        conversation: conversation,
        subject:      build_subject,
        issue:        @message.truncate(500),
        status:       "open",
        priority:     "normal",
        source:       source_type
      )

      notify_support_team(ticket)

      conversation.update!(
        handoff_mode: true,
        escalated_at: Time.current,
        status:       "escalated"
      )

      {
        type:          "human_escalation",
        message:       escalation_message,
        ticket_id:     ticket.id,
        ticket_number: "T-#{ticket.id.to_s.rjust(5, '0')}"
      }
    end

    private

    def build_subject
      prefix =
        if return_or_refund?
          "Return/Refund Request"
        elsif payment_issue?
          "Payment Issue"
        else
          "Support Request"
        end

      "#{prefix}: #{@message.truncate(50)}"
    end

    def escalation_message
      if customer_requested?
        "I've connected you with our support team. A ticket has been created — an agent will be with you shortly."
      else
        "I don't have enough information to resolve this automatically. I've escalated your request to our support team. A ticket has been created and an agent will follow up."
      end
    end

    def source_type
      customer_requested? ? "customer_requested_human" : "ai_escalation"
    end

    def customer_requested?
      @message.match?(/\b(human|agent|representative|live agent|talk to|speak to|connect me|support team|customer service)\b/i)
    end

    def return_or_refund?
      @message.match?(/\b(return|refund|exchange|replace)\b/i)
    end

    def payment_issue?
      @message.match?(/\b(payment|charge|bill|invoice|dispute|credit)\b/i)
    end

    def notify_support_team(ticket)
      vr = (@shop.ai_shopper_configuration&.visibility_rules || {}).with_indifferent_access
      return unless vr[:ticket_email_notification].to_s == "true"

      support_email = vr[:support_email].presence
      return if support_email.blank?

      TicketNotificationMailer.new_ticket(ticket: ticket, shop: @shop).deliver_later
    rescue => e
      Rails.logger.error("TicketNotificationMailer failed: #{e.class} #{e.message}")
    end
  end
end
