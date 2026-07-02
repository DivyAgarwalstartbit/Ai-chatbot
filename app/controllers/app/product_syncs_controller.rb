class App::ProductSyncsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: [ :create, :sync_status ]

  PER_PAGE = 10

  def show
    @search             = params[:search].to_s.strip
    @products_count     = current_shop.products.count
    @products_synced_at = current_shop.products_synced_at

    scope = current_shop.products.includes(:product_variants).order(created_at: :desc)
    scope = scope.where("title ILIKE :q OR handle ILIKE :q", q: "%#{@search}%") if @search.present?

    @filtered_count = scope.count
    @total_pages    = [ (@filtered_count / PER_PAGE.to_f).ceil, 1 ].max
    @current_page   = [ [ params[:page].to_i, 1 ].max, @total_pages ].min

    @products = scope
      .offset((@current_page - 1) * PER_PAGE)
      .limit(PER_PAGE)

    render(partial: "table_content") if request.xhr?
  end

  def create
     Rails.logger.info(
    "============== PRODUCT SYNC CLICKED =============="
  )
    shop = current_shop
    shop.update!(sync_status: "syncing")

    BulkProductSyncJob.perform_later(shop.id)

    render json: { success: true }
  end

  def sync_status
    render json: { status: current_shop.sync_status }
  end

  def current_shop
    Shop.find_by!(
      shopify_domain:
        current_shopify_session.shop
    )
  end
end
