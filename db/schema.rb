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

ActiveRecord::Schema[8.1].define(version: 2026_06_04_105833) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

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
    t.bigint "customer_id", null: false
    t.datetime "ended_at"
    t.integer "message"
    t.string "role"
    t.string "session_id"
    t.bigint "shop_id", null: false
    t.datetime "started_at"
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
    t.text "content"
    t.datetime "created_at", null: false
    t.vector "embedding"
    t.bigint "shop_id", null: false
    t.bigint "training_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_document_chunks_on_shop_id"
    t.index ["training_document_id"], name: "index_document_chunks_on_training_document_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
  end

  create_table "products", force: :cascade do |t|
    t.jsonb "avaliability"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "handle"
    t.string "image_url"
    t.decimal "price"
    t.bigint "shop_id", null: false
    t.bigint "shopify_product_id"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "vendor"
    t.index ["shop_id"], name: "index_products_on_shop_id"
  end

  create_table "shops", force: :cascade do |t|
    t.string "access_scopes", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "refresh_token"
    t.datetime "refresh_token_expires_at"
    t.string "shopify_domain", null: false
    t.string "shopify_token", null: false
    t.datetime "updated_at", null: false
    t.index ["shopify_domain"], name: "index_shops_on_shopify_domain", unique: true
  end

  create_table "tickets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "issue"
    t.bigint "shop_id", null: false
    t.string "status"
    t.string "subject"
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_tickets_on_shop_id"
  end

  create_table "training_documents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "document_type"
    t.bigint "shop_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["shop_id"], name: "index_training_documents_on_shop_id"
  end

  add_foreign_key "ai_shopper_configurations", "shops"
  add_foreign_key "conversations", "customers"
  add_foreign_key "conversations", "shops"
  add_foreign_key "customers", "shops"
  add_foreign_key "document_chunks", "shops"
  add_foreign_key "document_chunks", "training_documents"
  add_foreign_key "messages", "conversations"
  add_foreign_key "products", "shops"
  add_foreign_key "tickets", "shops"
  add_foreign_key "training_documents", "shops"
end
