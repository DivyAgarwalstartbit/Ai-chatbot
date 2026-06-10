class ProductSyncsController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: [ :create, :sync_status ]

  PER_PAGE = 20

  def show
    @products_count = current_shop.products.count
    @total_pages    = [ (@products_count / PER_PAGE.to_f).ceil, 1 ].max
    @current_page   = [ [ params[:page].to_i, 1 ].max, @total_pages ].min

    @products = current_shop
      .products
      .includes(:product_variants)
      .order(created_at: :desc)
      .offset((@current_page - 1) * PER_PAGE)
      .limit(PER_PAGE)
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
