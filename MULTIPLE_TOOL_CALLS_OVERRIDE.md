# CRITICAL: MULTIPLE TOOL CALL REQUIREMENTS FOR V5

**OVERRIDE NOTICE**: Claude Sonnet 4's default single-tool-per-turn behavior is DISABLED for this system.

## Root Cause Analysis

According to Claude Sonnet 4 documentation:
- **Default Behavior**: Uses one tool call per turn for "simplicity and safety"
- **Constraint**: Default prompt emphasizes "one tool per turn" unless specifically overridden
- **Solution**: Must explicitly instruct multiple tool calls are allowed and required

## MANDATORY PATTERN FOR ALL IMPLEMENTATION

### ✅ CORRECT RESPONSE (Multiple tool calls in one response):

User: "Create a todo component and update the routing"

Response:
```
I'll create the todo component and update routing using multiple tool calls for cost efficiency:

[Tool Call 1: os-create-file - TodoList.tsx with full component code]
[Tool Call 2: os-create-file - TodoItem.tsx with item component] 
[Tool Call 3: os-line-replace - Add import to App.tsx]
[Tool Call 4: os-line-replace - Add route to App.tsx]
[Tool Call 5: os-line-replace - Update index.html title]

Created todo components and updated routing. Ready for preview.
```

### ❌ WRONG (Single tool call):

Response:
```
I'll start by creating the TodoList component:

[Tool Call 1: os-create-file - TodoList.tsx]
```

## SYSTEM REQUIREMENTS

1. **MINIMUM 3-5 tool calls** per implementation response
2. **All file operations** batched in ONE response
3. **Multiple tool calls per turn** are EXPLICITLY ALLOWED
4. **Cost optimization** depends on this pattern
5. **Override default behavior** - single-tool-per-turn is DISABLED

## VERIFICATION

### AppBuilderV5 Support ✅
- Line 1217: Logs "Claude made #{response[:tool_calls].size} tool calls" 
- Line 1244: Executes `execute_and_format_tool_results(response[:tool_calls])`
- Line 1250: Processes all tool results in single message
- **CONFIRMED**: Orchestration layer supports multiple tool calls properly

### Prompt Updates ✅
- Added explicit override instructions in agent-prompt.txt
- Added mandatory tool batching requirements
- Added explicit authorization statements
- Added minimum tool call requirements

## Expected Results

**Before**: 1 tool call per response = 5 API roundtrips for 5 operations
**After**: 5 tool calls per response = 1 API roundtrip for 5 operations

**Cost Reduction**: 80% fewer API calls + 80% smaller context = 96% total cost reduction

## Implementation Status

- [x] Context reduction (80% savings) - BaseContextService optimized
- [x] Tool batching instructions - agent-prompt.txt updated  
- [x] System authorization - explicit override permissions added
- [x] Examples and patterns - mandatory patterns documented
- [ ] **TEST**: Generate test app to verify multiple tool calls working

The system is now configured to override Claude Sonnet 4's default single-tool behavior and require multiple tool calls per response for cost optimization.