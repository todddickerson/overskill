# Service to transform @/assets/ imports to R2-compatible asset resolver calls
# Automatically replaces import patterns during file saves

module Ai
  class R2AssetTransformer
    ASSET_IMPORT_PATTERN = /@\/assets\/([^'"\s]+)/
    ASSET_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .svg .ico .woff .woff2 .ttf .otf .mp4 .webm .mp3 .wav .pdf].freeze
    
    def initialize(app)
      @app = app
    end
    
    # Transform file content to use R2 asset resolver instead of @/assets/ imports
    def transform_content(content, file_path)
      return content unless should_transform_file?(file_path)
      
      Rails.logger.info "[R2Transform] Transforming asset imports in #{file_path}"
      
      transformed_content = content.dup
      transformations = []
      
      # Find all @/assets/ patterns
      transformed_content.scan(ASSET_IMPORT_PATTERN) do |asset_path|
        full_match = $&
        transformations << {
          pattern: full_match,
          asset_path: asset_path.first,
          match: full_match
        }
      end
      
      # Apply transformations
      transformations.each do |transform|
        replacement = generate_replacement(transform, file_path)
        transformed_content.gsub!(transform[:pattern], replacement)
        
        Rails.logger.info "[R2Transform] Replaced: #{transform[:pattern]} -> #{replacement}"
      end
      
      # Add import statement if transformations were made
      if transformations.any?
        transformed_content = add_asset_resolver_import(transformed_content, file_path)
      end
      
      transformed_content
    end
    
    private
    
    def should_transform_file?(file_path)
      # Only transform React/JS/TS files
      ['.jsx', '.tsx', '.js', '.ts'].any? { |ext| file_path.end_with?(ext) }
    end
    
    def generate_replacement(transform, file_path)
      asset_path = transform[:asset_path]
      
      # Check if this is likely an import statement vs inline usage
      if transform[:match].include?('import') || transform[:match].include?('from')
        # Import statement: import logo from "@/assets/logo.png"
        # Replace with: import { useAssetUrl } from './assetResolver'; const logo = useAssetUrl('assets/logo.png');
        generate_import_replacement(asset_path)
      else
        # Inline usage: <img src="@/assets/logo.png" />  
        # Replace with: <img src={assetResolver.resolve('assets/logo.png')} />
        generate_inline_replacement(asset_path)
      end
    end
    
    def generate_import_replacement(asset_path)
      # For import statements, we'll replace with a useAssetUrl hook call
      # This requires more complex transformation, so for now use direct resolver call
      "assetResolver.resolve('assets/#{asset_path}')"
    end
    
    def generate_inline_replacement(asset_path)
      # For inline usage in JSX or string contexts
      "assetResolver.resolve('assets/#{asset_path}')"
    end
    
    def add_asset_resolver_import(content, file_path)
      # Check if import already exists
      return content if content.include?('assetResolver')
      
      # Add import at the top of the file
      import_statement = if file_path.end_with?('.jsx', '.tsx')
        "import assetResolver from './assetResolver';\n"
      else
        "const { assetResolver } = require('./assetResolver');\n"  
      end
      
      # Find the best place to insert the import
      lines = content.split("\n")
      insert_index = find_import_insertion_point(lines)
      
      lines.insert(insert_index, import_statement.chomp)
      lines.join("\n")
    end
    
    def find_import_insertion_point(lines)
      # Find the last import statement or the first non-comment line
      last_import_index = -1
      
      lines.each_with_index do |line, index|
        if line.strip.start_with?('import ') || line.strip.start_with?('const ') && line.include?('require(')
          last_import_index = index
        elsif line.strip.start_with?('//') || line.strip.start_with?('/*') || line.strip.empty?
          # Skip comments and empty lines
          next
        else
          # First non-import, non-comment line found
          break
        end
      end
      
      last_import_index + 1
    end
    
    # Enhanced transformation for complex import statements
    def transform_import_statements(content)
      # Pattern: import varName from "@/assets/file.ext"
      import_pattern = /import\s+(\w+)\s+from\s+['"]@\/assets\/([^'"]+)['"]/
      
      content.gsub(import_pattern) do |match|
        var_name = $1
        asset_path = $2
        
        # Replace with React hook usage
        "const #{var_name} = useAssetUrl('assets/#{asset_path}')"
      end
    end
    
    # Transform JSX img src attributes
    def transform_jsx_src_attributes(content)
      # Pattern: src="@/assets/file.ext" or src='@/assets/file.ext'
      src_pattern = /src=['"]@\/assets\/([^'"]+)['"]/
      
      content.gsub(src_pattern) do |match|
        asset_path = $1
        "src={assetResolver.resolve('assets/#{asset_path}')}"
      end
    end
    
    # Transform CSS url() functions
    def transform_css_urls(content, file_path)
      return content unless file_path.end_with?('.css', '.scss', '.sass')
      
      # Pattern: url(@/assets/file.ext)
      url_pattern = /url\(['"]?@\/assets\/([^'")]+)['"]?\)/
      
      content.gsub(url_pattern) do |match|
        asset_path = $1
        # For CSS, we need to use CSS custom properties or generate URLs at build time
        "url(var(--asset-#{asset_path.gsub('/', '-').gsub('.', '-')}))"
      end
    end
    
    # Advanced transformation with full parsing
    def transform_advanced(content, file_path)
      transformed = content.dup
      
      # Transform import statements
      transformed = transform_import_statements(transformed)
      
      # Transform JSX attributes
      transformed = transform_jsx_src_attributes(transformed)
      
      # Transform CSS if applicable
      transformed = transform_css_urls(transformed, file_path)
      
      # Add necessary imports
      if transformed != content
        transformed = add_enhanced_imports(transformed, file_path)
      end
      
      transformed
    end
    
    def add_enhanced_imports(content, file_path)
      imports_needed = []
      
      if content.include?('useAssetUrl')
        imports_needed << 'useAssetUrl'
      end
      
      if content.include?('assetResolver.resolve')
        imports_needed << 'assetResolver'
      end
      
      return content if imports_needed.empty?
      
      # Create import statement
      if file_path.end_with?('.jsx', '.tsx')
        if imports_needed.include?('assetResolver') && imports_needed.include?('useAssetUrl')
          import_statement = "import assetResolver, { useAssetUrl } from './assetResolver';"
        elsif imports_needed.include?('useAssetUrl')
          import_statement = "import { useAssetUrl } from './assetResolver';"
        else
          import_statement = "import assetResolver from './assetResolver';"
        end
      else
        import_statement = "const { assetResolver } = require('./assetResolver');"
      end
      
      # Add import
      lines = content.split("\n")
      insert_index = find_import_insertion_point(lines)
      lines.insert(insert_index, import_statement)
      lines.join("\n")
    end
  end
end