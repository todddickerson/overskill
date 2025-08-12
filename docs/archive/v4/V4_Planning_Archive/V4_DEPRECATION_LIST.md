# V4 Deprecation List - Files to Remove/Update

## 🔴 URGENT: Update These Files

### AI_APP_STANDARDS.md
**Action**: Remove INSTANT MODE entirely
- Delete lines 22-78 (INSTANT MODE section)
- Delete lines 93-100+ (INSTANT MODE file structure)
- Keep only PRO MODE as the standard
- Update default behavior to always use Vite/TypeScript

### CLAUDE.md
**Action**: Update deployment architecture section
- Remove "No Build Tools" philosophy
- Remove CDN React references
- Update to Vite build pipeline
- Keep Cloudflare Worker deployment

---

## 🗑️ Delete These Files

### Services (CDN/No-Build Approach)
```
app/services/deployment/fast_preview_service.rb     # CDN React approach
app/services/deployment/cloudflare_preview_service.rb  # Base service for CDN
```

### Old Orchestrators
```
app/services/ai/app_update_orchestrator.rb         # V1 - obsolete
app/services/ai/app_update_orchestrator_v2.rb      # V2 - replaced by V3
```

### Old Documentation
```
docs/phase1-phase2-implementation-summary.md
docs/phase3-implementation-progress.md
docs/phase3-complete-summary.md
docs/ai-app-builder-improvement-plan.md
docs/FINAL-IMPLEMENTATION-REPORT.md
docs/comprehensive-app-generation-flow-analysis.md
docs/auth-implementation-status.md                  # Old auth approach
```

### Test Files (if any remain)
```
test_*.rb                                          # All test scripts in root
debug_*.rb                                         # All debug scripts
check_*.rb                                         # All check scripts
fix_*.rb                                           # All fix scripts
```

---

## ⚠️ Keep for Reference (Mark as Deprecated)

### V3 Orchestrator
```
app/services/ai/app_update_orchestrator_v3_unified.rb
# Add comment: DEPRECATED - Replaced by AppBuilderV4
# Keep until V4 is stable
```

### Integration Plan Docs
```
docs/CLAUDE4_V3_INTEGRATION_FINAL.md
# Keep as historical reference
# Shows what we tried with V3
```

---

## ✅ Keep These (They're Good!)

### Services to Integrate into V4
```
app/services/ai/line_replace_service.rb           # Surgical edits - INTEGRATE
app/services/ai/smart_search_service.rb          # Code search - INTEGRATE
app/services/ai/context_cache_service.rb         # Caching - KEEP
app/services/ai/anthropic_client.rb              # Direct API - KEEP
```

### Deployment (With Updates)
```
app/services/deployment/cloudflare_secret_service.rb  # Worker secrets - KEEP
# Update to work with Vite builds
```

### Analytics & Git
```
app/services/analytics/app_analytics_service.rb   # Analytics - KEEP
app/services/version_control/git_service.rb      # Git integration - KEEP
app/services/ai/image_generation_service.rb      # Image gen - KEEP
```

---

## 📝 Migration Notes

1. **Before deleting**: Ensure no active apps depend on CDN approach
2. **Backup**: Keep a backup branch with old files
3. **Update imports**: Check all controllers/jobs for references
4. **Test**: Verify V4 works before removing V3
5. **Documentation**: Update all user-facing docs

---

## 🎯 End Goal

After cleanup:
- ONE orchestrator (AppBuilderV4)
- ONE build system (Vite)
- ONE file structure (pages/components)
- ONE deployment pipeline (Build → Worker)
- NO confusion between modes

---

*Created: August 11, 2025*
*Purpose: Clean up codebase for V4 implementation*