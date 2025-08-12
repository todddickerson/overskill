# V4 Implementation: Critical Questions Requiring Decisions

## 🔴 BLOCKING QUESTIONS (Must Answer Before Starting)

### 1. **Build Environment Architecture**
**Decision Needed**: Where and how do Node.js builds actually run?

**Options & Questions**:
- **Docker + AWS ECS**: Do we have ECS cluster? Resource limits? Cost per build?
- **AWS Lambda**: Can Lambda handle npm install + Vite build in 15min timeout?
- **Local Docker**: Only for development? How to scale for production?

**Missing Details**:
- Build queue management (what if 10 apps build simultaneously?)
- Build isolation (prevent cross-app contamination)
- npm registry access from containers
- Build artifact storage (where do built files go temporarily?)
- Build logs visibility (how do users see build progress/errors?)

### 2. **Template Storage Decision**
**Decision Needed**: Where do we store shared template files?

**Options**:
- **A) Git Repository**: Versioned, easy updates, but complex integration
- **B) Database**: Dynamic, Rails-integrated, but harder to version
- **C) Filesystem**: Simple, fast, but hard to update across environments

**Critical Questions**:
- Template versioning - how do we update templates without breaking existing apps?
- Template dependencies - how do we manage npm packages in templates?
- Template testing - how do we validate templates work before using them?

### 3. **Database Connection Strategy**
**Decision Needed**: How do Cloudflare Workers connect to Supabase?

**Questions**:
- **Service Account**: Do we need dedicated Supabase service user for table creation?
- **Connection Pooling**: How do Workers efficiently connect to Supabase?
- **RLS Policy Timing**: When are policies created? During app creation or first access?
- **Permission Model**: Who has CREATE TABLE permissions in Supabase?

**Critical for Multi-tenancy**:
- Table cleanup for deleted apps
- Supabase project limits (500 tables = ~50 apps max)
- Schema migrations for app-scoped tables

### 4. **Environment Variable Injection**
**Decision Needed**: How does APP_ID get into the frontend code?

**Current Plan**: `window.ENV?.APP_ID` but how does it get there?

**Options**:
- **A) HTML Template**: Replace `{{APP_ID}}` during Worker deployment
- **B) Runtime API Call**: Fetch app config on page load
- **C) Build-time Injection**: Replace during Vite build

**Questions**:
- TypeScript types for app-scoped database wrapper?
- Hot reload compatibility?
- Security implications of exposing APP_ID?

### 5. **App File Storage Strategy** 
**Decision Needed**: Where do app files live during development?

**Options**:
- **A) Database Only**: All files in `app_files` table (current approach)
- **B) Hybrid**: Code in DB, assets in R2/S3
- **C) File System**: Local files, database metadata

**Questions**:
- File upload limits (max app size?)
- Binary file handling (images, fonts, etc.)
- Version control integration (git-like diffs?)
- Performance with large apps

### 6. **Error Recovery & User Notification**
**Decision Needed**: What happens when builds/deployments fail?

**Critical Scenarios**:
- npm install fails (network, package issues)
- Vite build fails (TypeScript errors, etc.)
- Worker deployment fails (size limit, API errors)
- Database connection fails

**Questions**:
- User notification strategy (email, UI, both?)
- Automatic retry logic?
- Rollback procedures?
- Error categorization and handling?

### 7. **Cost Attribution Model**
**Decision Needed**: How do we track and potentially bill costs per app?

**Cost Sources**:
- Build compute time (Docker/ECS)
- Cloudflare Worker executions
- R2 storage and requests
- Supabase database usage

**Questions**:
- Cost tracking granularity?
- Usage limits and quotas?
- Billing system integration needed?
- Free tier limits?

### 8. **Local Development Workflow**
**Decision Needed**: How do developers work locally with app-scoped database?

**Questions**:
- Local Supabase instance or shared dev database?
- How to preview apps locally with Worker constraints?
- Environment variable management across dev/staging/prod?
- Hot reload feasibility with Workers?

## 🟡 HIGH PRIORITY QUESTIONS (Need Soon)

### 9. **Cloudflare API Details**
- R2 authentication - bearer token correct or need signed URLs?
- Worker size validation - how to check before hitting 1MB limit?
- API rate limiting and backoff strategies?
- Custom domain setup process?

### 10. **Monitoring & Observability**
- What metrics to track? (Worker size, performance, errors, costs)
- User-facing dashboard requirements?
- Log aggregation strategy?
- Alerting thresholds?

### 11. **Security Model**
- Worker isolation guarantees between apps?
- API key storage and rotation?
- App user authentication within deployed apps?
- Security audit requirements?

### 12. **Performance & Scalability**
- Concurrent build limits?
- Database scaling with thousands of app-scoped tables?
- Load testing strategy?
- Performance baseline establishment?

## 🟢 MEDIUM PRIORITY QUESTIONS (Can Address During Implementation)

### 13. **Testing Strategy**
- Integration testing approach?
- End-to-end testing of deployed apps?
- Performance benchmarking?
- User acceptance testing protocols?

### 14. **Documentation Requirements**
- Developer setup guides depth?
- User onboarding flow design?
- API documentation scope?
- Troubleshooting guide content?

### 15. **Migration Planning**
- User communication strategy?
- Transition timeline?
- Data export capabilities?
- Support during migration?

## 📊 Decision Matrix

| Question | Urgency | Complexity | Impact | Blocker? |
|----------|---------|------------|--------|----------|
| Build Environment | 🔴 Critical | High | High | YES |
| Template Storage | 🔴 Critical | Medium | High | YES |
| Database Connection | 🔴 Critical | High | High | YES |
| Environment Variables | 🔴 Critical | Low | Medium | YES |
| File Storage | 🔴 Critical | Medium | High | YES |
| Error Recovery | 🔴 Critical | Medium | Medium | YES |
| Cost Attribution | 🔴 Critical | Low | Medium | YES |
| Local Development | 🔴 Critical | High | Medium | YES |

## 🎯 Recommended Decision Process

### Phase 1: Architecture Fundamentals (Today)
1. **Build Environment**: Confirm Docker + ECS approach with resource limits
2. **Template Storage**: Choose Git repository with versioning strategy  
3. **Database Connection**: Define service account and RLS policy creation timing
4. **File Storage**: Stick with database for now, optimize later

### Phase 2: Integration Details (Tomorrow)
5. **Environment Variables**: HTML template replacement approach
6. **Error Recovery**: Basic retry + user notification via UI
7. **Cost Attribution**: Simple tracking, billing integration later
8. **Local Development**: Shared dev Supabase instance for start

### Phase 3: Production Readiness (Week 1)
9. **Monitoring**: Basic metrics dashboard
10. **Security**: Security audit and hardening
11. **Performance**: Load testing and optimization
12. **Documentation**: Setup guides and troubleshooting

## 🚨 Critical Path Dependencies

```
Build Environment Decision
    ↓
Template Storage Decision  
    ↓
Database Connection Strategy
    ↓
Environment Variable Injection
    ↓ 
Start Implementation
```

**Bottom Line**: We need to make **8 critical architectural decisions** before we can start implementation. These decisions cascade into each other, so we need to address them in order.

**Recommended**: Let's go through these 8 questions systematically and make decisions on each one before writing any V4 code.