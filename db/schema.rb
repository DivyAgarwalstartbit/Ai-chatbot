# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_09_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_shopper_configurations", force: :cascade do |t|
    t.string "assistant_avatar_url"
    t.string "assistant_name"
    t.string "brand_tone"
    t.datetime "created_at", null: false
    t.jsonb "default_queries"
    t.text "greeting"
    t.string "language"
    t.bigint "shop_id", null: false
    t.jsonb "starter_prompts"
    t.jsonb "sync_state"
    t.datetime "updated_at", null: false
    t.jsonb "visibility_rules"
    t.boolean "widget_enabled"
    t.jsonb "widget_settings"
    t.index ["shop_id"], name: "index_ai_shopper_configurations_on_shop_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.datetime "ended_at"
    t.datetime "last_message_at"
    t.string "page_url"
    t.datetime "reviewed_at"
    t.string "session_id"
    t.bigint "shop_id", null: false
    t.datetime "started_at"
    t.string "status", default: "open"
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_conversations_on_customer_id"
    t.index ["shop_id"], name: "index_conversations_on_shop_id"
  end

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name"
    t.string "last_name"
    t.string "phone"
    t.bigint "shop_id", null: false
    t.bigint "shopify_customer_id"
    t.datetime "updated_at", null: false
    t.string "visitor_id"
    t.index ["shop_id"], name: "index_customers_on_shop_id"
  end

  create_table "document_chunks", force: :cascade do |t|
    t.integer "chunk_index"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "embedded_at"
    t.vector "embedding", limit: 768
    t.bigint "shop_id", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.bigint "training_document_id"
    t.datetime "updated_at", null: false
    t.index ["embedding"], name: "index_document_chunks_on_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["shop_id"], name: "index_document_chunks_on_shop_id"
    t.index ["source_type", "source_id"], name: "index_document_chunks_on_source_type_and_source_id"
    t.index ["training_document_id", "chunk_index"], name: "index_document_chunks_on_doc_and_chunk_index"
    t.index ["training_document_id"], name: "index_document_chunks_on_training_document_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata"
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "product_variants", force: :cascade do |t|
    t.boolean "available", default: true
    t.decimal "compare_at_price"
    t.datetime "created_at", null: false
    t.integer "inventory_quantity", default: 0
    t.jsonb "options", default: {}, null: false
    t.decimal "price"
    t.bigint "product_id", null: false
    t.bigint "shop_id", null: false
    t.bigint "shopify_variant_id"
    t.string "sku"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_variants_on_product_id"
    t.index ["shop_id", "shopify_variant_id"], name: "index_product_variants_on_shop_id_and_shopify_variant_id", unique: true
    t.index ["shop_id"], name: "index_product_variants_on_shop_id"
  end

  create_table "products", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "handle"
    t.string "image_url"
    t.bigint "shop_id", null: false
    t.bigint "shopify_product_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["shop_id", "shopify_product_id"], name: "index_products_on_shop_and_shopify_id", unique: true
    t.index ["shop_id"], name: "index_products_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.string "access_scopes", default: "", null: false
    t.string "charge_id"
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.boolean "paid", default: false, null: false
    t.string "plan"
    t.string "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.string "shopify_domain", null: false
    t.string "shopify_token", null: false
    t.string "sync_status", default: "idle", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
  end

  create_table "tickets", force: :cascade do |t|
    t.bigint "conversation_id"
    t.datetime "created_at", null: false
    t.bigint "customer_id"
    t.string "issue"
    t.string "priority", default: "normal"
    t.bigint "shop_id", null: false
    t.string "source"
    t.string "status", default: "open"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_tickets_on_conversation_id"
    t.index ["customer_id"], name: "index_tickets_on_customer_id"
    t.index ["shop_id", "status"], name: "index_tickets_on_shop_id_and_status"
    t.index ["shop_id"], name: "index_tickets_on_shop_id"
  end

  create_table "training_documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "document_type"
    t.text "embedding_error"
    t.string "embedding_status", default: "pending", null: false
    t.text "processing_error"
    t.string "processing_status", default: "pending", null: false
    t.bigint "shop_id", null: false
    t.text "shopify_content"
    t.string "source_type", default: "manual_entry", null: false
    t.datetime "synced_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["embedding_status"], name: "index_training_documents_on_embedding_status"
    t.index ["processing_status"], name: "index_training_documents_on_processing_status"
    t.index ["shop_id"], name: "index_training_documents_on_shop_id"
    t.index ["source_type"], name: "index_training_documents_on_source_type"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_shopper_configurations", "shops"
  add_foreign_key "conversations", "customers"
  add_foreign_key "conversations", "shops"
  add_foreign_key "customers", "shops"
  add_foreign_key "document_chunks", "shops"
  add_foreign_key "document_chunks", "training_documents"
  add_foreign_key "messages", "conversations"
  add_foreign_key "product_variants", "products"
  add_foreign_key "product_variants", "shops"
  add_foreign_key "products", "shops"
  add_foreign_key "tickets", "conversations"
  add_foreign_key "tickets", "customers"
  add_foreign_key "tickets", "shops"
  add_foreign_key "training_documents", "shops"
end
