# Text Streaming Fix - Tool Details Open by Default

## Summary
Modified the tool calls details element in the agent reply view to be open by default, allowing users to see tool execution details immediately without needing to click "Show All".

## Changes Made

### File: `app/views/account/app_editors/_agent_reply_v5.html.erb`

1. **Added `open` attribute** to the `<details>` element (line 336)
   - This makes the details element expanded by default when the page loads
   
2. **Changed initial toggle text** from "Show All" to "Hide" (line 342)
   - Since the element is now open by default, the initial text reflects the hide action

### Before:
```erb
<details class="mb-3 p-2 bg-gray-50 dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700"
         data-state-preserving-target="details"
         data-details-id="tools_<%= message.id %>"
         data-action="toggle->state-preserving#detailsToggled">
  <summary>
    ...
    <span ... >Show All</span>
  </summary>
```

### After:
```erb
<details class="mb-3 p-2 bg-gray-50 dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700"
         data-state-preserving-target="details"
         data-details-id="tools_<%= message.id %>"
         data-action="toggle->state-preserving#detailsToggled"
         open>
  <summary>
    ...
    <span ... >Hide</span>
  </summary>
```

## How It Works

The existing `state_preserving_controller.js` Stimulus controller continues to work as before:
- It saves the user's preference (open/closed state) in sessionStorage
- When the page reloads or updates via Action Cable, it restores the user's preference
- The toggle text automatically updates between "Show All" and "Hide" based on the details element's state

## User Experience

- **Default behavior**: Tool execution details are visible immediately when a message with tool calls is displayed
- **User control**: Users can click "Hide" to collapse the details if they prefer a cleaner view
- **Persistence**: The user's preference (open/closed) is remembered across page updates and reloads

This change improves transparency by showing AI tool usage by default while still giving users control to hide it if desired.