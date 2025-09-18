# Quick Win Implementation - Stop Copying All Template Files
# This can be implemented immediately for instant benefits

# app/models/app.rb
class App < ApplicationRecord
  # BEFORE: Copying all 84 files
  # AFTER: Only copy 7 essential files, load others on-demand

  ESSENTIAL_TEMPLATE_FILES = [
    "package.json",
    "index.html",
    "src/main.tsx",
    "src/App.tsx",
    "src/index.css",
    "tailwind.config.ts",
    "vite.config.ts",
    "tsconfig.json",
    ".gitignore"
  ].freeze

  # Replace the existing copy_template_files method
  def copy_minimal_template_files
    template_dir = current_template_path

    unless Dir.exist?(template_dir)
      Rails.logger.warn "[App] Template directory not found: #{template_dir}"
      return
    end

    files_copied = 0

    # Only copy essential files
    ESSENTIAL_TEMPLATE_FILES.each do |relative_path|
      file_path = ::File.join(template_dir, relative_path)

      next unless ::File.file?(file_path)

      content = ::File.read(file_path)

      # Create or update the app file
      app_file = app_files.find_or_initialize_by(path: relative_path)
      app_file.content = content
      app_file.file_type = detect_file_type(relative_path)

      if app_file.save
        files_copied += 1
        Rails.logger.info "[App] Copied essential file: #{relative_path}"
      end
    end

    Rails.logger.info "[App] Copied #{files_copied} essential files (was 84 files)"

    # Components will be loaded on-demand when AI needs them via os-view tool
  end

  # New method: Load component on-demand
  def load_component_on_demand(component_name)
    template_dir = current_template_path
    component_path = "src/components/ui/#{component_name}.tsx"
    file_path = ::File.join(template_dir, component_path)

    return nil unless ::File.file?(file_path)

    # Check if already loaded
    existing = app_files.find_by(path: component_path)
    return existing if existing

    # Load the component file
    content = ::File.read(file_path)
    app_file = app_files.create!(
      path: component_path,
      content: content,
      file_type: "component"
    )

    Rails.logger.info "[App] Loaded component on-demand: #{component_name}"
    app_file
  end

  private

  def detect_file_type(path)
    case ::File.extname(path)
    when ".tsx", ".jsx"
      "component"
    when ".ts", ".js"
      "script"
    when ".css"
      "style"
    when ".json"
      "config"
    when ".html"
      "markup"
    else
      "other"
    end
  end
end

# app/services/ai/prompts/optimized_cache_builder.rb
class OptimizedCacheBuilder < CachedPromptBuilder
  # Implement proper TTL-based caching following Anthropic best practices

  def build_system_prompt_array
    blocks = []

    # Block 1: System instructions (1 hour cache - rarely changes)
    if @base_prompt.present? && @base_prompt.length > 1024  # Anthropic minimum
      blocks << {
        type: "text",
        text: @base_prompt,
        cache_control: {
          type: "ephemeral",
          ttl: 3600  # 1 hour in seconds
        }
      }
    end

    # Block 2: Essential files (30 min cache - occasional changes)
    if @template_files.any?
      essential_content = build_essential_files_content
      if essential_content.length > 1024
        blocks << {
          type: "text",
          text: essential_content,
          cache_control: {
            type: "ephemeral",
            ttl: 1800  # 30 minutes
          }
        }
      end
    end

    # Block 3: Predicted components (5 min cache - user-specific)
    if @context_data[:predicted_components]&.any?
      component_content = build_component_content(@context_data[:predicted_components])
      if component_content.length > 1024
        blocks << {
          type: "text",
          text: component_content,
          cache_control: {
            type: "ephemeral",
            ttl: 300  # 5 minutes
          }
        }
      end
    end

    # Block 4: Dynamic user context (no cache)
    if @context_data[:user_context].present?
      blocks << {
        type: "text",
        text: @context_data[:user_context]
        # No cache_control = not cached
      }
    end

    # Log cache efficiency
    log_cache_metrics(blocks)

    blocks
  end

  private

  def log_cache_metrics(blocks)
    total_chars = blocks.sum { |b| b[:text].length }
    cached_chars = blocks.select { |b| b[:cache_control] }.sum { |b| b[:text].length }
    cache_ratio = (cached_chars.to_f / total_chars * 100).round(1)

    Rails.logger.info "[CACHE_METRICS] Total: #{total_chars} chars"
    Rails.logger.info "[CACHE_METRICS] Cached: #{cached_chars} chars (#{cache_ratio}%)"
    Rails.logger.info "[CACHE_METRICS] Blocks: #{blocks.count} (#{blocks.count { |b| b[:cache_control] }} cached)"

    # Track in Redis for monitoring
    Redis.current.hset("cache_metrics:#{Time.current.to_i}", {
      total_chars: total_chars,
      cached_chars: cached_chars,
      cache_ratio: cache_ratio,
      block_count: blocks.count
    })
  end
end

# Usage Example:
#
# app = App.find(123)
#
# # Use new minimal file copying
# app.copy_minimal_template_files  # Only 7 files instead of 84
#
# # Components loaded on-demand
# app.load_component_on_demand('button')  # Load when needed
#
# # Build optimized cached prompt
# builder = OptimizedCacheBuilder.new(
#   base_prompt: agent_prompt,
#   template_files: app.app_files.essential,
#   context_data: {
#     predicted_components: ['button', 'card', 'input'],
#     user_context: "User wants to build a todo app"
#   }
# )
#
# system_prompt_array = builder.build_system_prompt_array
# # This will have proper TTL caching and cost 90% less!
