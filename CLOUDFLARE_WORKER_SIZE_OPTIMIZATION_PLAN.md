# Cloudflare Worker Size Optimization Plan

## Executive Summary

**Problem**: Apps are exceeding Cloudflare Worker's 10MB size limit due to embedding all assets (images, fonts, etc.) directly in the Worker script as base64-encoded JSON. Recent app analysis shows 6.6MB of images alone in a 6.83MB total bundle.

**Solution**: Implement a hybrid deployment strategy using R2 storage for assets while keeping code in Workers, with progressive optimization phases.

---

## Current State Analysis

### Size Breakdown (Latest App: Pageforge, ID: 1027)
- **Total Size**: 6.83 MB (7,157,741 bytes)
- **Images**: 6.6 MB (4 JPG files)
  - testimonial-mike.jpg: 1.96 MB
  - testimonial-sarah.jpg: 1.93 MB
  - testimonial-jenny.jpg: 1.61 MB
  - hero-image.jpg: 1.11 MB
- **Code**: ~200 KB (TypeScript/React components)
- **Other**: ~13 KB (JSON, CSS, configs)

### Root Cause
The `Deployment::CloudflarePreviewService#generate_worker_script_with_built_files` method embeds ALL built files directly into the Worker script via `built_files_as_json`, creating a massive JavaScript file with embedded base64 assets.

---

## Implementation Strategy

### Phase 1: R2 Asset Offloading (Immediate Fix)
**Goal**: Move all static assets to R2, keep Worker under 5MB

#### 1.1 R2 Upload Service
```ruby
# app/services/deployment/r2_asset_service.rb
class Deployment::R2AssetService
  def initialize(app)
    @app = app
    @bucket = ENV['CLOUDFLARE_R2_BUCKET']
    @endpoint = ENV['CLOUDFLARE_R2_ENDPOINT']
  end
  
  def upload_assets(built_files)
    asset_urls = {}
    
    built_files.each do |path, file_data|
      if should_upload_to_r2?(path, file_data)
        url = upload_to_r2(path, file_data)
        asset_urls[path] = url
      end
    end
    
    asset_urls
  end
  
  private
  
  def should_upload_to_r2?(path, file_data)
    # Upload if: image, font, video, or file > 50KB
    is_asset = path.match?(/\.(jpg|jpeg|png|gif|webp|svg|ico|woff|woff2|ttf|mp4|webm)$/i)
    is_large = file_data[:content].bytesize > 50_000
    
    is_asset || is_large
  end
end
```

#### 1.2 Modified Worker Script
```javascript
// Instead of embedding files, reference R2 URLs
const ASSET_URLS = {
  "src/assets/hero.jpg": "https://r2.overskill.app/app-1027/src/assets/hero.jpg",
  // ... other assets
};

const INLINE_FILES = {
  "index.html": { content: "...", content_type: "text/html" },
  // Only small, critical files embedded
};

async function serveFile(path) {
  // Try inline files first
  if (INLINE_FILES[path]) {
    return new Response(INLINE_FILES[path].content, {
      headers: { 'Content-Type': INLINE_FILES[path].content_type }
    });
  }
  
  // Redirect to R2 for assets
  if (ASSET_URLS[path]) {
    return Response.redirect(ASSET_URLS[path], 301);
  }
  
  return new Response('Not found', { status: 404 });
}
```

### Phase 2: AI Tool Integration
**Goal**: Teach AI to use R2 URLs when generating images

#### 2.1 Update Image Generation Service
```ruby
# app/services/ai/image_generation_service.rb
def generate_and_save_image(prompt:, width:, height:, target_path:, **options)
  result = generate_image(prompt: prompt, width: width, height: height)
  
  if result[:success]
    # Upload to R2 immediately
    r2_url = upload_to_r2(@app.id, target_path, result[:image_data])
    
    # Save reference in AppFile (not the actual image data)
    file = @app.app_files.find_or_initialize_by(path: target_path)
    file.content = "<!-- R2_ASSET: #{r2_url} -->"
    file.metadata = { 
      r2_url: r2_url, 
      size: result[:image_data].bytesize,
      generated_at: Time.current
    }
    file.save!
    
    # Return R2 URL for AI to use
    result.merge(
      path: target_path,
      url: r2_url,
      instruction: "Use URL: #{r2_url} instead of local path"
    )
  else
    result
  end
end
```

#### 2.2 Update AI Tool Response Format
```ruby
# When AI calls generate-image tool, return:
{
  success: true,
  path: "src/assets/hero.jpg",
  url: "https://r2.overskill.app/app-1027/src/assets/hero.jpg",
  usage_instruction: "Reference this image using the URL in your HTML/CSS:\n<img src='https://r2.overskill.app/app-1027/src/assets/hero.jpg' alt='Hero' />"
}
```

### Phase 3: Build Process Optimization
**Goal**: Split build output into code and assets

#### 3.1 Enhanced Vite Build Service
```ruby
class Deployment::ViteBuildService
  def build_app!
    # ... existing build process ...
    
    # Separate files by type
    code_files = {}
    asset_files = {}
    
    built_files.each do |path, data|
      if is_asset_file?(path, data)
        asset_files[path] = data
      else
        code_files[path] = data
      end
    end
    
    {
      success: true,
      code_files: code_files,    # For Worker
      asset_files: asset_files,  # For R2
      stats: {
        code_size: calculate_size(code_files),
        asset_size: calculate_size(asset_files),
        total_files: built_files.count
      }
    }
  end
end
```

### Phase 4: Advanced Optimizations

#### 4.1 Workers KV for Small, Frequently Accessed Data
```javascript
// Store small, frequently accessed files in KV
// KV: 25MB value limit, faster than R2 for small files
await env.ASSETS_KV.put('app-1027-index.css', cssContent);
```

#### 4.2 D1 for Structured App Metadata
```sql
-- Store app configuration in D1
CREATE TABLE app_assets (
  app_id TEXT,
  path TEXT,
  r2_url TEXT,
  size INTEGER,
  content_type TEXT,
  created_at TIMESTAMP
);
```

#### 4.3 Service Bindings for Multi-Worker Architecture
```javascript
// Split large apps across multiple Workers
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    if (url.pathname.startsWith('/api/')) {
      // Delegate to API Worker
      return env.API_WORKER.fetch(request);
    }
    
    if (url.pathname.startsWith('/assets/')) {
      // Delegate to Assets Worker
      return env.ASSETS_WORKER.fetch(request);
    }
    
    // Handle main app
    return handleAppRequest(request, env);
  }
}
```

---

## Decision Points Requiring Clarification

### 1. **Asset Serving Strategy**
**Options**:
- A) **Direct R2 URLs** (Recommended)
  - Pros: Simple, no Worker overhead, unlimited storage
  - Cons: Separate domain, CORS configuration needed
- B) **Worker Proxy**
  - Pros: Same domain, can add auth/transformations
  - Cons: Worker CPU usage, complexity

**Recommendation**: Start with A, add B selectively for protected assets

### 2. **Image Generation Storage**
**Options**:
- A) **Immediate R2 Upload** (Recommended)
  - AI generates → uploads to R2 → returns URL
  - Pros: Never hits Worker size limit
  - Cons: Requires R2 setup during generation
- B) **Lazy Upload During Deployment**
  - Store in AppFiles, upload during deploy
  - Pros: Simpler generation flow
  - Cons: Can still hit Rails storage limits

**Recommendation**: A for production, with B as fallback

### 3. **Migration Strategy for Existing Apps**
**Options**:
- A) **On-Demand Migration**
  - Migrate when app is next deployed
  - Pros: No immediate work
  - Cons: Some apps remain broken
- B) **Batch Migration Script**
  - Migrate all apps immediately
  - Pros: Fixes all issues at once
  - Cons: Requires downtime/coordination

**Recommendation**: B for critical apps, A for others

### 4. **CDN Configuration**
**Options**:
- A) **R2 Custom Domain** (pub.overskill.app)
  - Configure R2 bucket with custom domain
  - Pros: Better branding, automatic CDN
  - Cons: Additional DNS setup
- B) **Direct R2 URLs**
  - Use xxx.r2.cloudflarestorage.com
  - Pros: Works immediately
  - Cons: Less professional URLs

**Recommendation**: Start with B, implement A within a week

---

## Implementation Checklist

### Immediate Actions (Day 1)
- [ ] Create R2AssetService class
- [ ] Modify CloudflarePreviewService to separate assets
- [ ] Update deployment to upload images to R2
- [ ] Test with existing large app (Pageforge)

### Short Term (Week 1)
- [ ] Update ImageGenerationService to use R2
- [ ] Modify AI tool responses to include R2 URLs
- [ ] Create migration script for existing apps
- [ ] Set up R2 custom domain

### Medium Term (Week 2-3)
- [ ] Implement KV caching for small files
- [ ] Add D1 for asset metadata
- [ ] Create monitoring dashboard for asset usage
- [ ] Optimize build process for parallel uploads

### Long Term (Month 1-2)
- [ ] Implement service bindings for large apps
- [ ] Add image transformation via Workers
- [ ] Create asset versioning system
- [ ] Implement smart caching strategies

---

## Cost Analysis

### Current (Embedded Assets)
- Worker requests: $0.30 per million
- Worker CPU: High (parsing large scripts)
- Storage: Counted against Worker size

### Optimized (R2 + Workers)
- Worker requests: $0.30 per million (same)
- Worker CPU: Low (smaller scripts)
- R2 Storage: $0.015 per GB/month
- R2 Operations: $0.36 per million Class A operations
- **Estimated Savings**: 50-70% reduction in Worker CPU time

---

## Monitoring & Success Metrics

### Key Metrics
1. **Worker Size**: Target < 5MB (50% of limit)
2. **Deployment Success Rate**: Target > 99%
3. **Asset Load Time**: Target < 100ms P95
4. **R2 Storage Usage**: Monitor growth rate
5. **Cost per App**: Track R2 + Worker costs

### Alerts
- Worker size > 8MB (80% of limit)
- R2 upload failures
- Asset 404 errors
- Deployment timeouts

---

## Rollback Plan

If R2 integration fails:
1. Feature flag to disable R2 uploads
2. Revert to embedded assets (with size checks)
3. Implement temporary file size limits
4. Use CDN for largest assets only

---

## Appendix: R2 Configuration

### Environment Variables (Already Set)
```bash
CLOUDFLARE_R2_ACCESS_KEY_ID=5dff052cf3fc16ccd7e8e4539fc94512
CLOUDFLARE_R2_SECRET_ACCESS_KEY=e2090bd4c0315c0463ac5cff2931ec2a3abf7391acd5fb9024871c4c7d2863dd
CLOUDFLARE_R2_BUCKET=overskill-apps-dev
CLOUDFLARE_R2_ENDPOINT=https://e03523c149209369c46ebc10b8a30b43.r2.cloudflarestorage.com
```

### R2 Bucket Structure
```
overskill-apps-dev/
├── app-{uuid}/
│   ├── assets/
│   │   ├── images/
│   │   ├── fonts/
│   │   └── videos/
│   ├── builds/
│   │   └── v{timestamp}/
│   └── generated/
│       └── ai-images/
```

### CORS Configuration for R2
```json
{
  "CORSRules": [{
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }]
}
```

---

## Next Steps

1. **Review this plan** and provide feedback on decision points
2. **Prioritize** implementation phases based on business needs
3. **Assign resources** for implementation
4. **Set timeline** for each phase

**Estimated Timeline**: 
- Phase 1 (R2 Offloading): 2-3 days
- Phase 2 (AI Integration): 2-3 days
- Phase 3 (Build Optimization): 3-4 days
- Phase 4 (Advanced): 1-2 weeks

**Total Effort**: ~2-3 weeks for full implementation