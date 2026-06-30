# frozen_string_literal: true

class ConversationsController < AuthenticatedController
  PER_PAGE = 14

  def index
    @shop_origin         = current_shopify_domain
    @host                = params[:host]
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count

    base                 = filtered_conversations
    @total_pages         = [ (base.count / PER_PAGE.to_f).ceil, 1 ].max
    @current_page        = [ [ params[:page].to_i, 1 ].max, @total_pages ].min
    @conversations       = base.offset((@current_page - 1) * PER_PAGE).limit(PER_PAGE)

    selected_id   = params[:conversation_id]
    @conversation = current_shop.conversations
                      .includes(:customer, :messages)
                      .find_by(id: selected_id) ||
                    @conversations.first
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
