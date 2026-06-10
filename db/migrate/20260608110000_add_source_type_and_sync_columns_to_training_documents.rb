class AddSourceTypeAndSyncColumnsToTrainingDocuments < ActiveRecord::Migration[8.1]
  def change
    # Tracks how the content originated: manual_entry | shopify_sync | uploaded_document
    add_column :training_documents, :source_type, :string, default: "manual_entry", null: false

    # The Shopify-synced body stored separately from manual content so both coexist
    add_column :training_documents, :shopify_content, :text

    # When the Shopify sync last ran successfully
    add_column :training_documents, :synced_at, :datetime

    add_index :training_documents, :source_type
  end
end
