class AddProcessingStatusToTrainingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :training_documents, :processing_status, :string, default: "pending", null: false
    add_column :training_documents, :processing_error, :text

    add_index :training_documents, :processing_status
  end
end
