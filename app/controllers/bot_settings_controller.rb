# frozen_string_literal: true

class BotSettingsController < AuthenticatedController
  def show
    @shop_origin = current_shopify_domain
    @host        = params[:host]
    @config      = current_shop.ai_shopper_configuration ||
                   current_shop.build_ai_shopper_configuration
  end

  def update
    @shop_origin = current_shopify_domain
    @host        = params[:host]
    @config      = current_shop.ai_shopper_configuration ||
                   current_shop.build_ai_shopper_configuration

    if @config.update(config_params)
      if request.xhr?
        head :ok
      else
        redirect_to bot_settings_path(shop: @shop_origin, host: @host, embedded: 1),
                    notice: "Settings saved."
      end
    else
      if request.xhr?
        render json: { errors: @config.errors.full_messages }, status: :unprocessable_entity
      else
        render :show, status: :unprocessable_entity
      end
    end
  end

  private

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def config_params
    permitted = params.require(:ai_shopper_configuration).permit(
      :assistant_name,
      :assistant_avatar_url,
      :greeting,
      :brand_tone,
      :widget_enabled,
      widget_settings: {},
      starter_prompts: [],
      default_queries: [],
      visibility_rules: {},
      store_details: {},
      sync_state: {}
    )

    permitted[:starter_prompts] = Array(permitted[:starter_prompts]).map(&:presence).compact
    permitted
  end
end
