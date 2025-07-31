# Overskill Development Handoff

## Current State Summary

The app generation and testing infrastructure is now fully functional. All 32 tests are passing, and the core workflow is operational:
- Apps can be created with AI-generated code
- Chat messages trigger code updates via background jobs
- User tracking is in place for audit trails
- Sidekiq queues are properly configured

### Update: Current Editor State
The app editor view has been examined and has the following state:
- Preview panel uses iframe with srcdoc attribute to render app HTML
- The `html_for_preview` helper exists and properly combines HTML/CSS/JS files
- Tabs controller exists and switches between Preview/Code/Files views
- File list shows in Code view with size_bytes correctly displayed
- Apps with generated content (like PurpleTask Pro) have files ready to preview

## Immediate Priority: Fix App Editor UI

The current app editor (http://localhost:3000/account/apps/{id}/editor) is missing critical features that exist in lovable.dev:

### What's Missing:
1. **Preview Panel**: Currently blank - needs to render app files in an iframe
2. **Code Editor**: No syntax highlighting, no file tree navigation
3. **Files Tab**: Not showing the list of app files
4. **Live Preview**: No hot reload when files change

### What We Have:
- `app.app_files` contains all generated files
- Basic editor layout with tabs (Preview, Code, Files)
- Chat interface is working
- Turbo Streams setup for real-time updates

## TODO List (Priority Order)

### 1. Fix Preview Panel (HIGH PRIORITY)
- [ ] Create preview route that serves app files (like `/preview/apps/:id/*path`)
- [ ] Implement iframe sandbox for security
- [ ] Handle index.html as default file
- [ ] Support CSS/JS file loading within preview
- [ ] Use Cloudflare R2 for production preview hosting

### 2. Implement Code Editor (HIGH PRIORITY)
- [ ] Add file tree sidebar showing all app_files
- [ ] Integrate CodeMirror or Monaco editor with syntax highlighting
- [ ] Support file switching without page reload
- [ ] Add save functionality (updates app_file content)
- [ ] Show file metadata (size, last modified)

### 3. Fix Files Tab (MEDIUM PRIORITY)
- [ ] List all app files with icons
- [ ] Support file download
- [ ] Add file upload capability
- [ ] Show file history/versions

### 4. Real-time Updates (MEDIUM PRIORITY)
- [ ] Broadcast file changes to preview iframe
- [ ] Update code editor when chat makes changes
- [ ] Show visual indicators for changed files
- [ ] Sync preview on file saves

### 5. GitHub Integration (MEDIUM PRIORITY)
- [ ] Implement GitHub OAuth flow
- [ ] Create repository from app
- [ ] Push app files to GitHub
- [ ] Set up webhooks for external changes
- [ ] Two-way sync between app files and repo

### 6. Deployment Features (LOW PRIORITY)
- [ ] One-click deploy to Cloudflare Workers
- [ ] Custom domain support
- [ ] Environment variables management
- [ ] Deployment history

## Technical Details

### Current File Structure
```ruby
# App model has these associations:
app.app_files        # All files for the app
app.app_versions     # Version history
app.app_generations  # AI generation history
app.app_chat_messages # Chat conversation
```

### Key Controllers
- `Account::AppEditorsController` - Main editor interface
- `Account::AppsController` - App management

### Services
- `Ai::AppGeneratorService` - Generates initial app code
- `ProcessAppUpdateJob` - Handles chat-based updates

### Environment Variables Needed
- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_R2_ACCESS_KEY_ID`
- `CLOUDFLARE_R2_SECRET_ACCESS_KEY`
- `CLOUDFLARE_R2_BUCKET_NAME`

## Recent Changes (for context)

1. Added user association to AppChatMessage
2. Fixed attribute naming (size → size_bytes)
3. Added ai_generation queue to Sidekiq
4. Made AppGeneration.started_at nullable
5. Fixed all test failures

## Development Tips

1. **Preview Implementation**: Start with a simple route that serves files directly from the database, then move to R2 for production
2. **Security**: Ensure preview iframe is sandboxed and files are served from a different subdomain
3. **Performance**: Consider caching compiled assets and using Turbo Frames for file switching
4. **Testing**: The lovable.dev example shows the target UX - match their file tree and preview behavior

## Commands to Get Started

```bash
# Start Rails server
bin/dev

# Run tests
bin/rails test

# Check current app files in console
App.find_by(slug: "purpletask-pro").app_files.pluck(:path, :file_type)

# Start Sidekiq (for background jobs)
bundle exec sidekiq
```

## Next Session Setup

1. Read this HANDOFF.md file
2. Check the current state of the editor at http://localhost:3000/account/apps/{any-app-id}/editor
3. Start with implementing the preview panel
4. Update this file as tasks are completed

Remember: The goal is to match the lovable.dev experience where users can see their app running in real-time as they make changes.