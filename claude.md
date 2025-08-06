# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## IMPORTANT: Check HANDOFF.md First!
**If a HANDOFF.md file exists in the root directory, read it FIRST for:**
- Current development context and state
- Active TODO items and priorities
- Recent changes and issues
- Next steps

**Update HANDOFF.md as you complete tasks by:**
1. Checking off completed items with [x]
2. Adding notes about implementation decisions
3. Updating the "Current State" section
4. Removing completed items when no longer relevant

## Project Overview

OverSkill is an AI-powered app marketplace platform built with Ruby on Rails (BulletTrain framework). It enables non-technical users to create, deploy, and monetize applications using natural language.

## AI Considerations

- Kimi-K2 may not work w/ function/tool calling always, if it's failing consider using Sonnet-4 or work around w/o Tool calling needed

## AI App Generation System (NEW - Enhanced with Tool Calling)

### Key Components
- **AI_APP_STANDARDS.md**: Comprehensive standards automatically included in every AI generation request
- **AppUpdateOrchestratorV2**: Enhanced orchestrator with tool calling for incremental file updates
- **Real-time Progress**: Shows files being created/edited in real-time during generation
- **30-minute timeout**: Extended from 10 minutes to handle complex app generation
- **Function/Tool Calling**: Uses OpenRouter's tool calling API for structured operations

### How It Works
1. **Analysis Phase**: AI analyzes app structure and user request
2. **Planning Phase**: Creates detailed execution plan with tool definitions
3. **Execution Phase**: Uses tool calling to incrementally update files with progress broadcasts
4. **Validation Phase**: Confirms all changes and updates preview

### Tool Functions Available
- `read_file`: Read complete file content
- `write_file`: Create or overwrite files
- `update_file`: Find/replace within files
- `delete_file`: Remove files
- `broadcast_progress`: Send real-time updates to user

### Testing AI Generation
```ruby
# Test the new orchestrator directly
rails console
message = AppChatMessage.last  # Get a test message
orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
orchestrator.execute!
```

[Rest of the file remains the same...]