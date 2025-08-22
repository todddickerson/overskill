# Live Preview Implementation Plan
## Approaching Lovable.dev-Level Real-Time Development Experience

### ✅ UPDATED: See COMPREHENSIVE_WFP_IMPLEMENTATION_PLAN.md for full integration

### Executive Summary

Based on comprehensive technical analysis of Lovable.dev's architecture and current OverSkill capabilities, this plan outlines a phased approach to implementing live preview functionality that provides instant visual feedback for AI-generated applications. The implementation leverages our existing Workers for Platforms architecture while adding sophisticated real-time preview capabilities.

**Key Updates from Comprehensive Plan:**
- Preview environments use WFP dispatch workers (5-10 second provisioning)
- WebSocket integration for real-time file synchronization
- Coordination with tool streaming for live updates
- Supabase integration for secure multi-tenant data access

### Current Architecture Assessment

**OverSkill Strengths:**
- ✅ Workers for Platforms deployment at scale (50,000+ apps)
- ✅ GitHub-per-app transparency and version control
- ✅ Vite-based modern build system with hot module replacement
- ✅ Database-first file storage with real-time synchronization
- ✅ Turbo Streams for real-time UI updates

**Gap Analysis vs Lovable.dev:**
- ❌ No instant preview environment (GitHub Actions takes 2-3 minutes)
- ❌ No visual editing capabilities (click-to-edit JSX components)
- ❌ Build failures not detected/fixed automatically
- ❌ No real-time code execution environment

### Recommended Architecture: Hybrid Cloud + WebContainer Approach

**Phase 1: Instant Cloud Dev Servers (Priority 1)**
- Leverage existing Fly.io/Cloudflare infrastructure
- Deploy ephemeral Vite dev servers using Workers for Platforms
- 5-10 second preview environment provisioning
- Real-time code sync from database to preview server

**Phase 2: Visual Editing System (Priority 2)**  
- Implement JSX component tagging similar to Lovable.dev
- Bidirectional mapping between visual elements and source code
- Click-to-edit functionality with real-time code updates
- Integration with existing AppFile database model

**Phase 3: WebContainer Integration (Future)**
- Client-side execution for instant previews
- Fallback to cloud servers for complex builds
- Browser compatibility considerations

### Technical Implementation Plan

#### Phase 1: Instant Cloud Dev Servers (4-6 weeks)

**1.1 Preview Environment Service**
```ruby
# app/services/deployment/instant_preview_service.rb
class Deployment::InstantPreviewService
  # Create ephemeral Vite dev server using WFP dispatch
  # Boot time target: 5-10 seconds vs current 2-3 minutes
  # Resource allocation: 100MB RAM, 0.1 CPU per preview
  
  def create_preview_environment(app)
    # 1. Generate preview worker script with Vite dev server
    # 2. Deploy to WFP namespace: overskill-preview-{app_id}
    # 3. Stream file contents from database to worker
    # 4. Return preview URL with WebSocket for real-time updates
  end
end
```

**1.2 Real-Time File Synchronization**
```ruby
# Update existing AppFile model
class AppFile < ApplicationRecord
  after_commit :sync_to_preview_server, on: [:create, :update]
  
  private
  
  def sync_to_preview_server
    return unless app.preview_environment_active?
    
    # Stream file changes to preview server via WebSocket
    PreviewSyncChannel.broadcast_to(
      app.preview_channel,
      { action: 'file_update', path: path, content: content }
    )
  end
end
```

**1.3 Preview URL Strategy**
- Production: `{app-id}.overskill.app` (static deployment)
- Preview: `preview-{app-id}.overskill.app` (live dev server)
- Development: `dev-{app-id}-{session-id}.overskill.app` (ephemeral)

#### Phase 2: Visual Editing System (6-8 weeks)

**2.1 JSX Component Tagging**
```typescript
// Custom Vite plugin for stable JSX IDs
export const jsxTaggingPlugin = () => ({
  name: 'jsx-tagging',
  transform(code, id) {
    if (id.endsWith('.tsx') || id.endsWith('.jsx')) {
      // Add data-overskill-id attributes to JSX elements
      // Generate stable IDs that persist across AI regeneration
      return addComponentTags(code);
    }
  }
});
```

**2.2 Visual Editor Interface**  
```erb
<!-- app/views/account/app_editors/_visual_editor.html.erb -->
<div id="visual-editor" data-controller="visual-editor">
  <iframe src="<%= @app.preview_url %>" 
          data-visual-editor-target="preview"
          data-action="load->visual-editor#enableClickToEdit">
  </iframe>
  
  <div data-visual-editor-target="codePanel" class="hidden">
    <!-- Real-time code editor for clicked component -->
  </div>
</div>
```

**2.3 Bidirectional Code Mapping**
```javascript
// app/assets/javascripts/controllers/visual_editor_controller.js
export default class extends Controller {
  enableClickToEdit() {
    const previewDocument = this.previewTarget.contentDocument;
    
    previewDocument.addEventListener('click', (e) => {
      const componentId = e.target.dataset.overskillId;
      if (componentId) {
        this.highlightComponent(componentId);
        this.loadComponentCode(componentId);
      }
    });
  }
  
  async loadComponentCode(componentId) {
    // Fetch JSX source for component from database
    // Display in side panel for editing
    // Real-time sync changes back to AppFile
  }
}
```

#### Phase 3: Advanced Features (8-12 weeks)

**3.1 Build Error Detection & Auto-Fix**
```ruby
# app/jobs/preview_build_monitor_job.rb  
class PreviewBuildMonitorJob < ApplicationJob
  def perform(app_id)
    app = App.find(app_id)
    
    # Monitor preview environment build status
    build_status = check_build_status(app.preview_url)
    
    if build_status[:errors].present?
      # Attempt automatic fixes using AI
      fix_result = attempt_automatic_fix(app, build_status[:errors])
      
      if fix_result[:success]
        # Broadcast success to chat
        broadcast_fix_success(app, fix_result)
      else
        # Report error back to AI chat conversation  
        broadcast_build_error(app, build_status[:errors])
      end
    end
  end
end
```

**3.2 WebContainer Integration (Future)**
```javascript
// Optional client-side execution for instant feedback
import { WebContainer } from '@webcontainer/api';

class ClientSidePreview {
  async initializeWebContainer() {
    this.webcontainer = await WebContainer.boot();
    // Mount file system from database
    // Provide instant preview without server roundtrip
  }
}
```

### Infrastructure Requirements

**Cloud Resources:**
- Estimated cost: $200-500/month for 1000 active preview environments
- Memory: 100MB per preview server (vs 10MB for static deployment)
- CPU: 0.1 core per active preview (burst to 0.5 for builds)
- Storage: Ephemeral, sourced from database in real-time

**Database Optimization:**
- Add indexes for real-time file queries
- Consider Redis caching for frequently accessed files
- WebSocket connection pooling for preview synchronization

### Risk Assessment

**Technical Risks:**
- Preview server resource consumption (mitigation: auto-cleanup after 30min idle)
- Build complexity in constrained environment (mitigation: fallback to GitHub Actions)
- WebSocket connection limits (mitigation: connection pooling)

**Operational Risks:**
- Increased infrastructure costs (mitigation: usage-based resource allocation)
- Preview server management complexity (mitigation: leverage existing WFP orchestration)

### Success Metrics

**Phase 1 Targets:**
- Preview environment boot time: < 10 seconds (vs current 2-3 minutes)
- File sync latency: < 500ms
- Preview server uptime: > 99.5%

**Phase 2 Targets:**
- Visual edit accuracy: > 95% successful code mapping
- Click-to-edit response time: < 200ms
- Code generation integration: seamless AI updates preserve visual mappings

**Phase 3 Targets:**
- Build error auto-fix rate: > 60% success
- WebContainer preview load time: < 2 seconds (when implemented)

### Implementation Timeline

**Week 1-2:** Infrastructure setup and preview service foundation
**Week 3-4:** Real-time file synchronization and WebSocket integration  
**Week 5-6:** Preview URL routing and environment management
**Week 7-10:** JSX tagging system and component identification
**Week 11-14:** Visual editor interface and click-to-edit functionality
**Week 15-18:** Build monitoring and automatic error detection
**Week 19-22:** AI-powered error fixing and chat integration
**Week 23-26:** Performance optimization and scaling

### Decision Points

**Architecture Choice:**
- **Recommended:** Hybrid cloud dev servers + future WebContainer integration
- **Alternative:** Pure WebContainer approach (higher compatibility risk)
- **Fallback:** Enhanced GitHub Actions with faster builds (minimal change)

**Visual Editing Scope:**
- **Phase 2A:** Click-to-highlight and show source code
- **Phase 2B:** Inline editing with real-time updates  
- **Phase 2C:** Visual style editing (colors, layout, typography)

### Next Steps

1. **Stakeholder Review:** Approve overall approach and phase prioritization
2. **Technical Spike:** 1-week proof-of-concept for instant preview deployment
3. **Resource Allocation:** Assign development team for Phase 1 implementation
4. **Infrastructure Planning:** Provision preview environment infrastructure

---

*This plan balances ambitious live preview capabilities with pragmatic implementation using our existing Workers for Platforms architecture. The phased approach allows for iterative improvement while delivering value at each stage.*