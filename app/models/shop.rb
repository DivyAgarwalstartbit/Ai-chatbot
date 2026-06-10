# frozen_string_literal: true

class Shop < ActiveRecord::Base
  include ShopifyApp::ShopSessionStorage

      has_many :products
    has_many :customers
    has_many :conversations
    has_many :training_documents
    has_many :document_chunks
    has_one :ai_shopper_configuration

    after_create_commit :sync_products


  def api_version
    ShopifyApp.configuration.api_version
  end

  def sync_products
    BulkProductSyncJob.perform_later(id)
  end
end
