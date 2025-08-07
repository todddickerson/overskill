# OpenAI API Key Setup

The autonomous testing system requires a valid OpenAI API key for GPT-5 integration.

## Current Status
- ❌ OPENAI_API_KEY is set to "dummy-key" (invalid)
- ✅ System correctly fails with clear error messages when API key is invalid
- ✅ No fallback to Anthropic (prevents tool_use_id mismatch errors)

## To Enable GPT-5 Testing

1. **Set the correct API key in your environment:**
   ```bash
   export OPENAI_API_KEY="your-openai-api-key-here"
   ```

2. **Or update your shell profile (.bashrc/.zshrc):**
   ```bash
   echo 'export OPENAI_API_KEY="your-openai-api-key-here"' >> ~/.zshrc
   source ~/.zshrc
   ```

3. **Test the system:**
   ```bash
   ruby test_autonomous.rb quick
   ```

## Expected Behavior

**With valid API key:**
- ✅ GPT-5 generates React apps successfully
- ✅ 100% success rate on simple counter/todo apps
- ✅ Real-time progress tracking

**With invalid API key (current):**
- ❌ Clear error: "Incorrect API key provided"
- ❌ 0% success rate
- ✅ Fast fail (< 0.2 seconds)
- ✅ No confusing Anthropic fallback errors

The system is designed to fail cleanly with invalid credentials rather than falling back to broken Anthropic integration.