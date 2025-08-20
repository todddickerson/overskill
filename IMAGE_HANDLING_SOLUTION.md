# Image Handling Solution for OverSkill Apps

## Current Status Analysis

### ✅ What Works:
1. **Image Generation**: DALL-E generates images successfully
2. **R2 Upload**: Images are uploaded to R2 at `https://pub.overskill.com/app-{id}/production/{path}`
3. **Placeholder Files**: Created with correct R2 URLs in HTML comments
4. **AssetResolver**: Template includes proper asset resolver that handles R2 URLs
5. **LazyImage**: Template includes LazyImage component that supports direct URLs

### ❌ Current Issues:
1. **Integration Gap**: Generated components aren't using the asset resolver properly
2. **Direct URL Usage**: Components need to use direct R2 URLs instead of relative paths
3. **Missing Connection**: Gap between placeholder files and actual component usage

## Solution for Future Apps

### 1. Update AI Prompting (app/services/ai/app_builder_v5.rb)

Add clear instructions for image handling:

```ruby
# In the system prompt for AI generation:
SYSTEM_PROMPT = <<~PROMPT
  When working with images in the app:
  
  1. ALWAYS use direct R2 URLs for images that have been generated
  2. Image placeholder files contain the R2 URL in HTML comments
  3. For generated images, use the pattern: https://pub.overskill.com/app-{APP_ID}/production/src/assets/{filename}
  4. Use the LazyImage component from '@/LazyImage' for lazy loading
  5. For direct image tags, use the full R2 URL in the src attribute
  
  Example for using a generated image:
  ```tsx
  import LazyImage from '@/LazyImage';
  
  // For lazy loading
  <LazyImage 
    src="https://pub.overskill.com/app-{APP_ID}/production/src/assets/hero.jpg"
    alt="Hero image"
    className="w-full h-auto"
  />
  
  // For direct img tag
  <img 
    src="https://pub.overskill.com/app-{APP_ID}/production/src/assets/hero.jpg"
    alt="Hero image"
  />
  ```
PROMPT
```

### 2. Create Image Helper Service

Create a new service to extract R2 URLs from placeholder files:

```ruby
# app/services/ai/image_url_extractor_service.rb
module Ai
  class ImageUrlExtractorService
    def initialize(app)
      @app = app
    end
    
    def extract_all_image_urls
      image_files = @app.app_files.where('path LIKE ?', 'src/assets/%')
      urls = {}
      
      image_files.each do |file|
        if file.content.match(/<!-- Image hosted on R2: (.+?) -->/)
          url = $1
          filename = File.basename(file.path)
          urls[filename] = url
        end
      end
      
      urls
    end
    
    def create_image_urls_module
      urls = extract_all_image_urls
      return if urls.empty?
      
      content = generate_image_urls_content(urls)
      
      file = @app.app_files.find_or_initialize_by(path: 'src/imageUrls.js')
      file.content = content
      file.file_type = 'javascript'
      file.team = @app.team
      file.save!
    end
    
    private
    
    def generate_image_urls_content(urls)
      <<~JS
        // Auto-generated image URL mappings
        // Generated at: #{Time.current.iso8601}
        
        export const imageUrls = {
          #{urls.map { |name, url| "'#{name}': '#{url}'" }.join(",\n  ")}
        };
        
        export function getImageUrl(imageName) {
          return imageUrls[imageName] || `https://pub.overskill.com/app-#{@app.id}/production/src/assets/${imageName}`;
        }
      JS
    end
  end
end
```

### 3. Hook into App Generation Process

Add to AppBuilderV5 after image generation:

```ruby
# In app_builder_v5.rb, after generating images:
def post_process_images
  # Extract all image URLs and create imageUrls.js
  image_extractor = Ai::ImageUrlExtractorService.new(@app)
  image_extractor.create_image_urls_module
  
  # Broadcast status
  broadcast_progress("Configuring image assets...")
end
```

### 4. Update Template Components

The template already has:
- ✅ AssetResolver that handles R2 URLs
- ✅ LazyImage component with direct URL support
- ✅ useAsset hook

### 5. AI Tool Instructions

Update AI tool service to provide better context:

```ruby
# In ai_tool_service.rb generate_image method:
def generate_image(args)
  # ... existing code ...
  
  if result[:success]
    # Provide clear usage instructions
    response = <<~MSG
      Image generated successfully!
      
      R2 URL: #{result[:url]}
      
      To use this image in your components:
      
      1. With LazyImage (recommended):
      ```tsx
      import LazyImage from '@/LazyImage';
      <LazyImage src="#{result[:url]}" alt="Description" />
      ```
      
      2. Direct img tag:
      ```tsx
      <img src="#{result[:url]}" alt="Description" />
      ```
      
      3. As background:
      ```css
      background-image: url('#{result[:url]}');
      ```
    MSG
    
    { 
      success: true, 
      content: response,
      url: result[:url],
      path: target_path,
      storage_method: 'r2'
    }
  end
end
```

## Implementation Checklist

- [ ] Update AI system prompts to include image handling instructions
- [ ] Create ImageUrlExtractorService
- [ ] Hook image URL extraction into app generation flow
- [ ] Update generate_image tool to provide clear usage instructions
- [ ] Test with a new app generation

## Expected Outcome

Future apps will:
1. Generate images and upload to R2 ✅
2. Automatically create imageUrls.js with all R2 URLs
3. Components will use direct R2 URLs
4. Images will load correctly on production

## Testing

To verify implementation:

```bash
# Generate a new app with images
rails c
app = App.create!(name: "Test App", team: Team.first)
service = Ai::ImageGenerationService.new(app)
service.generate_and_save_image(
  prompt: "A beautiful hero image",
  target_path: "src/assets/hero.jpg"
)

# Check placeholder file
app.app_files.find_by(path: "src/assets/hero.jpg").content
# Should contain: <!-- Image hosted on R2: https://pub.overskill.com/app-{id}/production/src/assets/hero.jpg -->

# Extract URLs
extractor = Ai::ImageUrlExtractorService.new(app)
extractor.create_image_urls_module

# Check imageUrls.js
app.app_files.find_by(path: "src/imageUrls.js").content
# Should contain proper R2 URLs
```