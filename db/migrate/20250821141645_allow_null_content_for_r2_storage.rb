class AllowNullContentForR2Storage < ActiveRecord::Migration[8.0]
  def change
    # Allow null content for R2-only storage
    change_column_null :app_files, :content, true
    
    # Add comment to explain why null is allowed
    change_column_comment :app_files, :content, 
      'File content stored in database. Can be null when content is stored in R2 only.'
  end
end
