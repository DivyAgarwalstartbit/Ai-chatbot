# frozen_string_literal: true

class KnowledgeBase::ShippingPoliciesController < AuthenticatedController
  skip_before_action :verify_authenticity_token, only: [:update]

  def show
    @shop_origin = current_shopify_domain
    @host = params[:host]
    @shipping_policy = current_shop.training_documents
                                   .find_or_initialize_by(document_type: "shipping_policy")
  end

  def update
    @shop_origin = current_shopify_domain
    @host = params[:host]
    @shipping_policy = current_shop.training_documents
                                   .find_or_initialize_by(document_type: "shipping_policy")

    @shipping_policy.assign_attributes(shipping_policy_params)
    @shipping_policy.title ||= "Shipping Policy"

    if @shipping_policy.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to knowledge_base_root_path(shop: @shop_origin, host: @host, embedded: 1), notice: "Shipping policy saved." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render :update, status: :unprocessable_entity }
        format.html { render :show, status: :unprocessable_entity }
      end
    end
  end

  private

  def current_shop
    @current_shop ||= Shop.find_by!(shopify_domain: current_shopify_domain)
  end

  def shipping_policy_params
    params.require(:training_document).permit(:content)
  end
end
