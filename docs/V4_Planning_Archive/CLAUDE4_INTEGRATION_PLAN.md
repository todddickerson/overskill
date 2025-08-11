# Claude 4 Integration Plan for V3 Unified Orchestrator

## Problem Analysis

### Current Situation
1. **Claude 4 models ARE available** via the Anthropic API (confirmed working)
   - `claude-opus-4-1-20250805` - Most capable model
   - `claude-sonnet-4-20250514` - Best for coding (72.7% SWE-bench)

2. **Tool calling behavior differs between models**:
   - **GPT-5**: Generates multiple files in a single response (3-10 tool calls)
   - **Claude 4**: Only generates 1 file per response, even when explicitly asked for multiple
   - **Claude 3.5**: Similar to Claude 4, tends toward single tool calls

3. **Root cause**: Claude's tool use is designed for iterative conversation
   - Claude makes a tool call → We process it → Send result back → Claude continues
   - This is fundamentally different from GPT-5's batch approach

## The HTML File Reveals Claude's Understanding

The single HTML file Claude creates is actually a **complete blueprint**:
```html
<!-- Claude creates script tags for ALL files it knows should exist -->
<script type="text/babel" src="src/lib/supabase.js"></script>
<script type="text/babel" src="src/components/TaskCard.jsx"></script>
<script type="text/babel" src="src/components/KanbanBoard.jsx"></script>
<script type="text/babel" src="src/pages/auth/Login.jsx"></script>
<script type="text/babel" src="src/pages/auth/SignUp.jsx"></script>
<script type="text/babel" src="src/pages/Dashboard.jsx"></script>
<script type="text/babel" src="src/App.jsx"></script>
```

This shows Claude:
1. ✅ Understands the full app architecture
2. ✅ Knows all files that need to be created
3. ❌ But stops after creating the first file

## Solution Architecture

### Option 1: Multi-Turn Conversation Loop (Claude-Native Approach)
```ruby
def execute_with_claude_conversation(initial_messages, tools)
  conversation = initial_messages.dup
  files_created = []
  max_turns = 10
  
  max_turns.times do |turn|
    # Make API call
    response = call_claude_api(conversation, tools)
    
    # Process any tool calls
    if has_tool_calls?(response)
      tool_results = process_tool_calls(response)
      files_created += tool_results[:files]
      
      # Add assistant response and tool results to conversation
      conversation << { role: "assistant", content: response['content'] }
      conversation << { role: "user", content: format_tool_results(tool_results) }
      
      # Check if we have all required files
      if all_required_files_created?(files_created)
        break
      else
        # Prompt to continue
        conversation << { 
          role: "user", 
          content: "Good! Now create the next file(s). Remaining files: #{missing_files.join(', ')}"
        }
      end
    else
      # No more tool calls, we're done
      break
    end
  end
  
  files_created
end
```

### Option 2: Parallel Step Execution (Simpler but Less Efficient)
```ruby
def execute_implementation(plan)
  # Process each step separately
  # Claude will create 1-2 files per step
  plan["steps"].each do |step|
    execute_step_with_tools(step, tools)
  end
end
```

### Option 3: Hybrid Approach with Smart Planning
```ruby
def execute_implementation(plan)
  # Group files by logical units
  file_groups = [
    { name: "foundation", files: ["index.html"] },
    { name: "core", files: ["src/App.jsx", "src/lib/supabase.js"] },
    { name: "auth", files: ["src/pages/auth/Login.jsx", "src/pages/auth/SignUp.jsx"] },
    { name: "features", files: ["src/pages/Dashboard.jsx", "src/components/*.jsx"] }
  ]
  
  file_groups.each do |group|
    prompt = build_focused_prompt(group)
    execute_with_claude_iterative(prompt, group[:files])
  end
end
```

## Recommended Implementation Path

### Phase 1: Enhanced Planning (Quick Win)
1. ✅ Already implemented: Better execution plan with multiple steps
2. Each step focuses on 1-2 files that Claude can handle
3. This should improve file generation from 1 to 6-8 files

### Phase 2: Add Conversation Loop for Claude
1. Detect when using Claude models
2. After receiving tool calls, check if all expected files were created
3. If not, continue the conversation with: "Please continue creating the remaining files"
4. Repeat until all files are created or max iterations reached

### Phase 3: Optimize Prompting
1. For Claude: Use explicit, numbered instructions
2. Emphasize "create ALL files before responding with text"
3. Consider using system prompts that work better with Claude's training

## Implementation Decision Matrix

| Approach | Complexity | Time to Implement | File Generation Success | API Calls |
|----------|------------|-------------------|------------------------|-----------|
| Current (Single Step) | Low | Done | 1 file | 1 |
| Multi-Step Plan | Low | 30 min | 6-8 files | 6-8 |
| Conversation Loop | Medium | 2 hours | All files | 3-5 |
| Hybrid Smart Groups | High | 4 hours | All files | 4 |

## Immediate Action Items

1. **Test multi-step approach** (already implemented)
   - This should work immediately
   - Claude should create 1-2 files per step
   - Total: 6-8 files across all steps

2. **Add file validation after each step**
   ```ruby
   def validate_step_completion(step, files_created)
     expected = step['files'] || []
     created = files_created.map(&:path)
     missing = expected - created
     
     if missing.any?
       Rails.logger.warn "[V3-Unified] Step incomplete. Missing: #{missing.join(', ')}"
       # Could retry or continue conversation here
     end
   end
   ```

3. **Monitor and log patterns**
   - Track which files Claude creates together
   - Identify optimal groupings for future optimization

## Testing Strategy

1. **Test 1**: Run with new multi-step plan
   - Expected: 6-8 files created
   - Each step should produce its designated files

2. **Test 2**: Add conversation continuation
   - After each step, if files are missing, ask Claude to continue
   - Expected: All files created

3. **Test 3**: Optimize step grouping
   - Based on Test 1 results, adjust which files are requested together
   - Goal: Minimize API calls while ensuring all files are created

## Success Metrics

- ✅ All 8 core files are created
- ✅ Files reference each other correctly
- ✅ App can be deployed and run
- ✅ Completion time < 90 seconds
- ✅ API calls < 10 per app generation

## Long-term Considerations

1. **Model-specific strategies**
   - GPT-5: Batch all files in one request
   - Claude 4: Use conversation loop
   - Claude 3.5: Similar to Claude 4
   - Fallback models: Simple step-by-step

2. **Caching and optimization**
   - Cache system prompts for Claude
   - Reuse conversation context across steps
   - Implement parallel processing where possible

3. **User experience**
   - Show real-time progress per file
   - Indicate which model is being used
   - Provide clear error messages if generation fails

## Conclusion

The issue isn't that Claude 4 can't create multiple files - it's that Claude's tool use is designed for conversational iteration. By embracing this pattern rather than fighting it, we can achieve full app generation with Claude 4 while maintaining compatibility with GPT-5's batch approach.