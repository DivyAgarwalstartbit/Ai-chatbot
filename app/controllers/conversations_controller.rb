# frozen_string_literal: true

class ConversationsController < AuthenticatedController
  def index
    @shop_origin        = current_shopify_domain
    @host               = params[:host]
    @conversations      = scoped_conversations
    @conversation       = nil
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count
  end

  def show
    @shop_origin        = current_shopify_domain
    @host               = params[:host]
    @conversations      = scoped_conversations
    @conversation       = current_shop.conversations
                            .includes(:customer, :messages)
                            .find(params[:id])
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count

    render :index
  end

  private

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def scoped_conversations
    scope = current_shop.conversations
              .includes(:customer, :messages)
              .order(last_message_at: :desc, created_at: :desc)

    scope = scope.where(status: params[:status]) if params[:status].present?

    if params[:q].present?
      q = "%#{params[:q]}%"
      scope = scope.joins(:customer)
                   .where(
                     "customers.first_name ILIKE :q OR customers.last_name ILIKE :q OR customers.email ILIKE :q OR customers.visitor_id ILIKE :q",
                     q: q
                   )
    end

    scope
  end
end
