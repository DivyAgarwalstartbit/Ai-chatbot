class AddUploadedContentToTrainingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :training_documents, :uploaded_content, :text
  end
end
