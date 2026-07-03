# frozen_string_literal: true

class ConversationsController < AuthenticatedController
  PER_PAGE = 14

  def index
    @shop_origin         = current_shopify_domain
    @host                = params[:host]
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count
    @active_tab          = params[:tab] == "tickets" ? "tickets" : "conversations"

    if @active_tab == "tickets"
      base          = filtered_tickets
      @total_pages  = [ (base.count / PER_PAGE.to_f).ceil, 1 ].max
      @current_page = [ [ params[:page].to_i, 1 ].max, @total_pages ].min
      @tickets      = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)
      selected_id   = params[:ticket_id]
      @ticket       = (selected_id.present? ? current_shop.tickets.includes(:customer, conversation: { messages: [] }).find_by(id: selected_id) : nil) ||
                      @tickets.first&.then { |t| current_shop.tickets.includes(:customer, conversation: { messages: [] }).find(t.id) }
    else
      base                 = filtered_conversations
      @total_pages         = [ (base.count / PER_PAGE.to_f).ceil, 1 ].max
      @current_page        = [ [ params[:page].to_i, 1 ].max, @total_pages ].min
      @conversations       = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)
      selected_id          = params[:conversation_id]
      @conversation        = current_shop.conversations
                               .includes(:customer, :messages)
                               .find_by(id: selected_id) ||
                             @conversations.first
    end
  end

  def update
    conversation = current_shop.conversations.find(params[:id])
    conversation.update!(status: params[:status]) if params[:status].present?
    render json: { success: true, status: conversation.status }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  def show
    @shop_origin         = current_shopify_domain
    @host                = params[:host]
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count
    @active_tab          = "conversations"

    base           = filtered_conversations
    @total_pages   = [ (base.count / PER_PAGE.to_f).ceil, 1 ].max
    @current_page  = [ [ params[:page].to_i, 1 ].max, @total_pages ].min
    @conversations = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)
    @conversation  = current_shop.conversations
                       .includes(:customer, :messages)
                       .find(params[:id])

    render :index
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

  def filtered_conversations
    scope = current_shop.conversations
              .includes(:customer, :messages)
              .order(last_message_at: :desc, created_at: :desc)

    scope = scope.where(status: params[:status]) if params[:status].present? && params[:status] != "All"

    if params[:q].present?
      q     = "%#{params[:q]}%"
      scope = scope.joins(:customer)
                   .where(
                     "customers.first_name ILIKE :q OR customers.last_name ILIKE :q OR customers.email ILIKE :q OR customers.visitor_id ILIKE :q",
                     q: q
                   )
    end

    scope
  end
end
