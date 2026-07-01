# frozen_string_literal: true

class TicketsController < AuthenticatedController
  PER_PAGE = 14

  def index
    @shop_origin         = current_shopify_domain
    @host                = params[:host]
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count

    base          = filtered_tickets
    @total_pages  = [ (base.count / PER_PAGE.to_f).ceil, 1 ].max
    @current_page = [ [ params[:page].to_i, 1 ].max, @total_pages ].min
    @tickets      = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)
    selected_id   = params[:ticket_id]
    @ticket       = (selected_id.present? ? current_shop.tickets.includes(:customer, conversation: { messages: [] }).find_by(id: selected_id) : nil) ||
                    @tickets.first&.then { |t| current_shop.tickets.includes(:customer, conversation: { messages: [] }).find(t.id) }
  end

  def show
    @shop_origin         = current_shopify_domain
    @host                = params[:host]
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count

    base          = filtered_tickets
    @total_pages  = [ (base.count / PER_PAGE.to_f).ceil, 1 ].max
    @current_page = [ [ params[:page].to_i, 1 ].max, @total_pages ].min
    @tickets      = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)
    @ticket       = current_shop.tickets
                      .includes(:customer, conversation: { messages: [] })
                      .find(params[:id])

    render :index
  end

  def reply
    ticket = current_shop.tickets
               .includes(:conversation, :customer)
               .find(params[:id])

    unless ticket.conversation
      return render json: { error: "No conversation linked to this ticket" }, status: :unprocessable_entity
    end

    content = params[:content].to_s.strip
    return render json: { error: "Message cannot be blank" }, status: :unprocessable_entity if content.blank?

    conversation = ticket.conversation
    message      = conversation.messages.create!(role: "agent", content: content)

    if conversation.status == "closed"
      # Conversation is closed — deliver reply to customer's registered email
      customer_email = ticket.customer&.email.presence

      if customer_email
        TicketReplyMailer.agent_reply(
          ticket:  ticket,
          message: message,
          shop:    current_shop
        ).deliver_later
        ticket.update!(status: "closed")
        render json: { success: true, message_id: message.id, delivery: "email", ticket_status: "closed" }
      else
        render json: { success: true, message_id: message.id, delivery: "none",
                       warning: "Customer has no registered email — message saved but not delivered" }
      end
    else
      # Conversation is open — push via WebSocket so the widget receives it live
      Rails.logger.info "Broadcasting to conversation_#{conversation.id}: #{message.content}"
      ActionCable.server.broadcast(
        "conversation_#{conversation.id}",
        {
          role:    "agent",
          content: message.content,
          time:    message.created_at.strftime("%-I:%M %p"),
          sender:  "Support Agent"
        }
      )
      render json: { success: true, message_id: message.id, delivery: "websocket" }
    end
  end

  def update
    ticket = current_shop.tickets.find(params[:id])
    ticket.update!(status: params[:status]) if params[:status].present?
    render json: { success: true, status: ticket.status }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  private

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def filtered_tickets
    scope = current_shop.tickets
              .includes(:customer, :conversation)
              .order(created_at: :desc)

    status_param = params[:status].presence
    scope = scope.where(status: status_param) if status_param && status_param != "All"

    if params[:q].present?
      q     = "%#{params[:q]}%"
      scope = scope.joins("LEFT JOIN customers ON customers.id = tickets.customer_id")
                   .where(
                     "tickets.subject ILIKE :q OR tickets.issue ILIKE :q OR customers.first_name ILIKE :q OR customers.last_name ILIKE :q OR customers.email ILIKE :q",
                     q: q
                   )
    end

    scope
  end
end
