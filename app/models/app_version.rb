class AppVersion < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  belongs_to :user, optional: true
  # 🚅 add belongs_to associations above.

  has_many :app_chat_messages, dependent: :nullify
  has_many :app_version_files, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :app, scope: true
  validates :user, scope: true, allow_blank: true
  validates :version_number, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    team.apps
  end

  def valid_users
    team.users
  end

  # Generate a display name based on changes made
  def generate_display_name!
    return if display_name.present?
    
    # Generate AI-powered summary of changes
    files_summary = generate_files_summary
    prompt = build_display_name_prompt(files_summary)
    
    generated_name = begin
      # Use OpenRouter for cost-effective text generation
      client = Ai::OpenRouterClient.new
      response = client.chat(
        [{ role: 'user', content: prompt }],
        max_tokens: 50,
        temperature: 0.3
      )
      # Extract content from response
      response.dig('choices', 0, 'message', 'content') || generate_simple_display_name
    rescue => e
      Rails.logger.error "Failed to generate display name: #{e.message}"
      # Fallback to simple name based on file changes
      generate_simple_display_name
    end
    
    update!(display_name: generated_name.strip)
    generated_name
  end
  
  def formatted_display_name
    display_name.presence || generate_display_name!
  end
  
  def has_files_data?
    files_snapshot.present? || app_version_files.exists?
  end
  
  def can_be_restored?
    has_files_data? || app.app_versions.where("files_snapshot IS NOT NULL").exists?
  end
  
  def formatted_file_changes
    app_version_files.includes(:app_file).map do |version_file|
      file_name = extract_file_name(version_file.app_file.path)
      file_type = extract_file_type(version_file.app_file.path)
      action_label = format_action_label(version_file.action)
      
      {
        action: version_file.action,
        action_label: action_label,
        file_name: file_name,
        file_type: file_type,
        full_path: version_file.app_file.path
      }
    end
  end
  
  private
  
  def generate_files_summary
    changes_by_action = app_version_files.includes(:app_file).group_by(&:action)
    
    summary_parts = []
    
    changes_by_action.each do |action, files|
      file_names = files.map { |f| extract_file_name(f.app_file.path) }
      case action
      when 'created'
        summary_parts << "created #{file_names.join(', ')}"
      when 'updated'
        summary_parts << "updated #{file_names.join(', ')}"
      when 'deleted'
        summary_parts << "deleted #{file_names.join(', ')}"
      when 'restored'
        summary_parts << "restored #{file_names.join(', ')}"
      end
    end
    
    summary_parts.join(', ')
  end
  
  def build_display_name_prompt(files_summary)
    changelog_context = changelog.present? ? "Context: #{changelog.first(200)}" : ""
    
    <<~PROMPT
      Generate a concise 2-4 word summary of these code changes:
      
      Files changed: #{files_summary}
      #{changelog_context}
      
      Examples of good summaries:
      - "Fix login errors"
      - "Add user dashboard"
      - "Update styling system"
      - "Complete checkout flow"
      - "Refactor data models"
      
      Summary:
    PROMPT
  end
  
  def generate_simple_display_name
    file_count = app_version_files.count
    
    if file_count == 1
      file = app_version_files.first
      file_name = extract_file_name(file.app_file.path)
      action = format_action_label(file.action)
      "#{action} #{file_name}"
    elsif file_count <= 3
      "Update #{file_count} files"
    else
      "Major code changes"
    end
  end
  
  def extract_file_name(path)
    # Handle empty or just filename cases
    return 'Root file' if path.blank? || path == '.'
    
    # Extract meaningful file name or component name
    file_name = File.basename(path, File.extname(path))
    
    # Handle empty file names (like hidden files or just extensions)
    if file_name.blank? || file_name == '.'
      # Use the full path or directory name
      return File.basename(path) if File.basename(path) != '.'
      return 'Config file'
    end
    
    # Convert common patterns to readable names
    case file_name.downcase
    when 'index', 'main', 'app'
      parent_dir = File.basename(File.dirname(path))
      if parent_dir == '.' || parent_dir.blank?
        file_name.capitalize
      else
        parent_dir.capitalize
      end
    when 'style', 'styles'
      'Styles'
    when 'component', 'components'
      'Components'
    when 'package'
      'Package config'
    when 'readme'
      'Documentation'
    else
      # Convert camelCase or snake_case to Title Case
      cleaned_name = file_name.gsub(/[_-]/, ' ').split.map(&:capitalize).join(' ')
      cleaned_name.presence || File.basename(path)
    end
  end
  
  def extract_file_type(path)
    ext = File.extname(path).downcase
    
    case ext
    when '.html', '.htm'
      'page'
    when '.js', '.jsx', '.ts', '.tsx'
      'component'
    when '.css', '.scss', '.sass'
      'styles'
    when '.json'
      'config'
    when '.md'
      'documentation'
    when '.vue'
      'component'
    when '.py'
      'script'
    when '.rb'
      'model'
    else
      'file'
    end
  end
  
  def format_action_label(action)
    case action
    when 'created'
      'Creating'
    when 'updated'
      'Editing'
    when 'deleted'
      'Removing'
    when 'restored'
      'Restoring'
    else
      'Modifying'
    end
  end

  # 🚅 add methods above.
end
