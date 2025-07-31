# AI Chat Response Workflow Feature Specification

## Overview
When a user sends a message to the AI assistant requesting changes to their app, the system should provide a multi-stage response flow that shows planning, execution, and completion states with appropriate UI feedback.

## User Flow

### 1. User Sends Request
- User types message in chat (e.g., "Add a dark mode toggle to the header")
- Message appears in chat immediately with user avatar

### 2. AI Planning Phase
**Visual State:**
- AI assistant message appears with "thinking" indicator
- Message content shows what AI is planning to do:
  ```
  I'll add a dark mode toggle to your header. Here's what I'll do:
  • Add a toggle button in the navigation area
  • Create CSS variables for light/dark themes
  • Add JavaScript to handle theme switching
  • Save theme preference in localStorage
  ```
- Status badge: "Planning..." with animated dots

### 3. AI Execution Phase
**Visual State:**
- Planning text remains but fades slightly
- New section appears below with spinner/progress indicator
- Status changes to: "Making changes..." with spinner
- Real-time updates as files are being modified:
  ```
  ✓ Updated index.html
  ⟳ Modifying styles.css...
  ⟳ Adding theme-switcher.js...
  ```

### 4. AI Completion Phase
**Visual State:**
- Spinner replaced with success checkmark
- Status changes to: "Changes complete"
- Dynamic link appears: "View changes in Version 1.0.1" 
- Sub-link: "Preview code diff"
- Summary of changes:
  ```
  Changes made:
  • Added dark mode toggle button to header
  • Created CSS variables for theming
  • Added theme switching logic
  • Theme preference saves to localStorage
  ```

### 5. AI Suggestions Phase
**Visual State:**
- Suggestion buttons appear below the summary:
  - "🔧 Refactor styles.css (getting large)"
  - "✨ Add theme transition animations"
  - "📱 Make toggle mobile-friendly"
  - "🎨 Add more theme color options"

**Interaction:**
- Clicking a suggestion drafts a new message in the input
- User can edit the drafted message before sending
- Example: Click "Add theme transition animations" → Input fills with "Add smooth transitions when switching between light and dark themes"

## Technical Implementation

### Components Needed

1. **Chat Message States Component**
   ```erb
   app/views/account/app_editors/_ai_message_states.html.erb
   - planning_state
   - executing_state  
   - completed_state
   - suggestions_state
   ```

2. **Turbo Streams Updates**
   ```ruby
   # Broadcast planning state
   broadcast_append_to "app_#{app.id}_chat",
     target: "chat_messages",
     partial: "ai_planning_message"
   
   # Update to executing state
   broadcast_replace_to "app_#{app.id}_chat",
     target: "ai_message_#{message.id}",
     partial: "ai_executing_message"
   ```

3. **AppVersion Integration**
   - Create AppVersion when changes complete
   - Generate diff view using CodeMirror
   - Link to version preview page

4. **CodeMirror Diff View**
   ```javascript
   // app/javascript/controllers/code_diff_controller.js
   import CodeMirror from 'codemirror'
   import 'codemirror/addon/merge/merge'
   
   // Show side-by-side diff
   CodeMirror.MergeView(element, {
     value: newCode,
     orig: oldCode,
     lineNumbers: true,
     mode: 'javascript',
     highlightDifferences: true
   })
   ```

5. **Suggestion Engine**
   ```ruby
   class Ai::SuggestionService
     def generate_suggestions(app, recent_changes)
       suggestions = []
       
       # Check file sizes
       if app.app_files.any? { |f| f.size_bytes > 5000 }
         suggestions << {
           icon: "🔧",
           text: "Refactor large files",
           prompt: "Can you help refactor the larger files to be more modular?"
         }
       end
       
       # Check for missing features based on app type
       # ... more logic
       
       suggestions
     end
   end
   ```

## UI/UX Considerations

1. **Animation & Transitions**
   - Smooth fade between states
   - Subtle pulse on status indicators
   - Progress animation during execution

2. **Accessibility**
   - ARIA labels for status changes
   - Screen reader announcements for state transitions
   - Keyboard navigation for suggestion buttons

3. **Error Handling**
   - Show clear error state if generation fails
   - Retry button
   - Error details in collapsible section

4. **Performance**
   - Debounce real-time file update notifications
   - Lazy load CodeMirror only when diff view requested
   - Cache previous versions for quick diff generation

## Database Schema Updates

```ruby
# Add to app_chat_messages
add_column :app_chat_messages, :planning_content, :text
add_column :app_chat_messages, :execution_steps, :jsonb, default: []
add_column :app_chat_messages, :suggestions, :jsonb, default: []
add_column :app_chat_messages, :app_version_id, :integer
add_index :app_chat_messages, :app_version_id
```

## Success Metrics
- Time from request to first planning message < 2s
- Clear visual feedback at each stage
- Users engage with suggestions 30%+ of the time
- Code diff view loads < 1s

## Future Enhancements
- Real-time collaborative editing during AI changes
- Undo/redo for AI modifications  
- Branch management for experimental changes
- Integration with GitHub PRs for review workflow