# frozen_string_literal: true

class TicketsController < AuthenticatedController
  def index
    @shop_origin         = current_shopify_domain
    @host                = params[:host]
    @tickets             = scoped_tickets
    @ticket              = nil
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count
  end

  def show
    @shop_origin         = current_shopify_domain
    @host                = params[:host]
    @tickets             = scoped_tickets
    @ticket              = current_shop.tickets
                             .includes(:customer, :conversation => { :messages => [] })
                             .find(params[:id])
    @conversations_count = current_shop.conversations.count
    @tickets_count       = current_shop.tickets.count

    render :index
  end

  def update
    @shop_origin = current_shopify_domain
    @host        = params[:host]
    ticket = current_shop.tickets.find(params[:id])
    ticket.update!(status: params[:status]) if params[:status].present?

    redirect_to ticket_path(
                  ticket,
                  shop:     @shop_origin,
                  host:     @host,
                  embedded: 1,
                  q:        params[:q],
                  status:   params[:status_filter]
                ),
                status: :see_other
  end

  private

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def scoped_tickets
    scope = current_shop.tickets
              .includes(:customer, :conversation)
              .order(created_at: :desc)

    status_param = params[:status].presence
    scope = scope.where(status: status_param) if status_param && status_param != "All"

    if params[:q].present?
      q = "%#{params[:q]}%"
      scope = scope.joins("LEFT JOIN customers ON customers.id = tickets.customer_id")
                   .where(
                     "tickets.subject ILIKE :q OR tickets.issue ILIKE :q OR customers.first_name ILIKE :q OR customers.last_name ILIKE :q OR customers.email ILIKE :q",
                     q: q
                   )
    end

    scope
  end
end
