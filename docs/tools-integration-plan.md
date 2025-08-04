# Tools Integration Plan: Lovable.dev-Inspired Features for OverSkill

## Executive Summary

This document outlines a plan to integrate AI-powered tools and capabilities similar to Lovable.dev into the OverSkill platform, while maintaining cost efficiency by leveraging Kimi-K2 via OpenRouter as our primary AI service.

## Updated Research: Kimi-K2 Deep Dive (August 2025)

### Key Technical Specifications
- **Architecture**: Mixture-of-Experts (MoE) with 1 trillion total parameters, 32 billion active per forward pass
- **Context Window**: 32,768 tokens (standard), up to 128K tokens for long-context inference
- **Training**: 15.5T tokens with zero training instability using MuonClip optimizer
- **Strengths**: Coding (65.8% SWE-Bench Verified), reasoning, tool use, agentic capabilities

### Critical Pricing Update (OpenRouter)
- **Input tokens**: $0.088 per 1M tokens (significantly lower than initially researched $0.15)
- **Output tokens**: $0.088 per 1M tokens (dramatically lower than initially researched $2.50)
- **Cost advantage**: ~3x cheaper than Claude Sonnet, ~100x cheaper than Claude Opus
- **Free tier**: Available through OpenRouter for testing

### Limitations and Known Issues
1. **No Native Vision**: Kimi-K2 does not support image/multimodal input (must use Kimi-VL separately)
2. **Tool Calling Issues**: Significant problems with OpenRouter function calling integration:
   - Generates JSON in text responses instead of proper tool calls
   - Causes "AI_NoObjectGeneratedError" in standard implementations
   - Multiple reported issues across platforms (AutoGen, Claude Code, Groq)
3. **Platform Dependencies**: Tool calling quality varies significantly by platform

### Strategic Implications for OverSkill
- **Cost Benefits**: Even more attractive than initially projected due to lower pricing
- **Technical Challenges**: Need custom tool calling implementation for reliable function use
- **Vision Workaround**: Must integrate separate vision models for image analysis features

## Current State Analysis

### OverSkill's Existing Capabilities
- ✅ AI-powered app generation via Kimi-K2 (OpenRouter)
- ✅ Chat-based iterative improvement system
- ✅ Live preview with iframe rendering
- ✅ File browser with syntax highlighting
- ✅ Code editor interface (split-screen like Lovable)
- ✅ Multi-step orchestrator for complex tasks
- ✅ Cloudflare Workers deployment pipeline

### Lovable.dev's Key Features We Could Integrate
- 🔧 Visual design tools (sketch-to-code, Figma import)
- 🔧 Multiple AI service integrations
- 🔧 Advanced debugging tools ("Try to Fix" functionality)
- 🔧 Real-time collaboration features
- 🔧 Template system and project remixing
- 🔧 Enhanced error handling and suggestions

## Critical Implementation Considerations

### Tool Calling Workaround Strategy
Given Kimi-K2's known issues with OpenRouter function calling, we need a custom implementation:

```ruby
class Ai::KimiToolCallHandler
  def execute_with_tools(prompt, available_tools = [])
    # Custom implementation to handle Kimi-K2's JSON-in-text responses
    tool_descriptions = build_tool_descriptions(available_tools)
    enhanced_prompt = build_tool_aware_prompt(prompt, tool_descriptions)
    
    response = OpenRouterClient.new.generate(enhanced_prompt)
    
    # Parse JSON from text response instead of relying on function calling
    if contains_tool_calls?(response)
      execute_parsed_tools(response, available_tools)
    else
      response
    end
  end
  
  private
  
  def build_tool_aware_prompt(prompt, tools)
    <<~PROMPT
      You are an AI assistant with access to the following tools:
      #{tools.map { |t| "- #{t[:name]}: #{t[:description]}" }.join("\n")}
      
      When you need to use a tool, respond with JSON in this exact format:
      {
        "tool_call": {
          "name": "tool_name",
          "arguments": { "key": "value" }
        },
        "reasoning": "Why you chose this tool"
      }
      
      User request: #{prompt}
    PROMPT
  end
  
  def contains_tool_calls?(response)
    response.include?('tool_call') && valid_json_structure?(response)
  end
  
  def execute_parsed_tools(response, available_tools)
    tool_data = JSON.parse(extract_json(response))
    tool_name = tool_data.dig('tool_call', 'name')
    arguments = tool_data.dig('tool_call', 'arguments')
    
    if tool = available_tools.find { |t| t[:name] == tool_name }
      tool[:handler].call(arguments)
    else
      "Tool #{tool_name} not found"
    end
  end
end
```

### Vision Capabilities Alternative
Since Kimi-K2 lacks native vision, implement a hybrid approach:

```ruby
class Ai::VisionAnalysisService
  def analyze_image(image_file, prompt)
    # Use Claude 3.5 Sonnet sparingly for vision tasks
    if complex_visual_analysis_needed?(prompt)
      ClaudeVisionService.new.analyze(image_file, prompt)
    else
      # Use simpler, cheaper alternatives for basic tasks
      extract_text_from_image(image_file) # OCR
    end
  end
  
  private
  
  def complex_visual_analysis_needed?(prompt)
    visual_keywords = ['design', 'layout', 'ui', 'mockup', 'sketch', 'wireframe']
    visual_keywords.any? { |keyword| prompt.downcase.include?(keyword) }
  end
end
```

## Phase 1: Enhanced AI Tools (Low Cost, High Impact)

### 1.1 Multi-Modal Input Support
**Goal**: Enable users to input designs via sketches, images, or descriptions

**Implementation**:
```ruby
# New service class
class Ai::MultiModalProcessorService
  def process_visual_input(image_file, prompt)
    # Use Kimi-K2's vision capabilities (if available) or fall back to description prompts
    if kimi_supports_vision?
      analyze_image_with_kimi(image_file, prompt)
    else
      # Use cost-effective image-to-text via cheaper models
      description = extract_visual_description(image_file)
      process_with_kimi("Based on this visual description: #{description}. #{prompt}")
    end
  end
  
  private
  
  def kimi_supports_vision?
    # Check Kimi-K2 vision capabilities
    false # Assume no for now, research needed
  end
end
```

**Cost Strategy**: 
- Primary: Use text-based descriptions of visual inputs
- Fallback: Integrate Claude 3.5 Sonnet only for complex visual analysis (pay-per-use)
- Research Kimi-K2's multimodal capabilities

### 1.2 Enhanced Debugging Assistant
**Goal**: Implement "Try to Fix" functionality without using credits for common errors

**Implementation**:
```ruby
class Ai::DebuggingAssistantService
  COMMON_FIXES = {
    'SyntaxError' => ->(error) { suggest_syntax_fixes(error) },
    'ReferenceError' => ->(error) { suggest_reference_fixes(error) },
    'TypeError' => ->(error) { suggest_type_fixes(error) },
    # Add more common patterns
  }.freeze
  
  def suggest_fix(error_message, code_context)
    # Try pattern-based fixes first (no AI cost)
    if common_fix = find_common_fix(error_message)
      return common_fix
    end
    
    # Use AI only for complex issues
    use_ai_for_debugging(error_message, code_context)
  end
  
  private
  
  def find_common_fix(error_message)
    COMMON_FIXES.each do |pattern, fix_fn|
      return fix_fn.call(error_message) if error_message.include?(pattern)
    end
    nil
  end
end
```

### 1.3 Template System and Project Remixing
**Goal**: Reduce AI costs by providing pre-built templates users can modify

**Implementation**:
```ruby
class Template < ApplicationRecord
  belongs_to :team
  has_many :template_files, dependent: :destroy
  
  scope :public_templates, -> { where(public: true) }
  scope :by_category, ->(category) { where(category: category) }
  
  def remix_for_user(user, modifications = {})
    # Clone template without AI generation
    new_app = self.clone_as_app(user.current_team)
    
    # Apply modifications using targeted AI prompts (lower cost)
    if modifications.present?
      Ai::TemplateModifierService.new(new_app).apply_changes(modifications)
    end
    
    new_app
  end
end
```

## Phase 2: Advanced Integration Features (Medium Cost)

### 2.1 Smart API Integration Assistant
**Goal**: Help users integrate external APIs with minimal AI overhead

**Implementation**:
```ruby
class Ai::ApiIntegrationService
  def suggest_integration(api_docs_url, user_intent)
    # Cache common API patterns to reduce AI calls
    cached_pattern = ApiPattern.find_by_endpoint_pattern(api_docs_url)
    return cached_pattern.generate_code(user_intent) if cached_pattern
    
    # Use AI for new APIs, but cache results
    integration_code = generate_with_kimi(api_docs_url, user_intent)
    cache_api_pattern(api_docs_url, integration_code)
    
    integration_code
  end
  
  private
  
  def cache_api_pattern(url, code)
    # Store successful patterns for reuse
    ApiPattern.create(
      endpoint_pattern: extract_pattern(url),
      template_code: generalize_code(code)
    )
  end
end
```

### 2.2 Intelligent Code Suggestions
**Goal**: Provide contextual code suggestions without constant AI calls

**Implementation**:
```ruby
class CodeSuggestionEngine
  def initialize(app)
    @app = app
    @context = build_context_cache
  end
  
  def suggest_next_steps(current_code)
    # Use pattern matching first
    pattern_suggestions = PatternMatcher.suggest(@context, current_code)
    return pattern_suggestions if pattern_suggestions.any?
    
    # Use AI sparingly for novel situations
    ai_suggestions = generate_ai_suggestions(current_code)
    cache_suggestions(current_code, ai_suggestions)
    
    ai_suggestions
  end
  
  private
  
  def build_context_cache
    {
      frameworks: detect_frameworks,
      common_patterns: extract_patterns,
      user_preferences: @app.user_coding_style
    }
  end
end
```

## Phase 3: Advanced Collaboration and Tools (Higher Cost, Premium Features)

### 3.1 Real-time Collaboration
**Goal**: Enable multiple users to work on apps simultaneously

**Implementation Strategy**:
- Use ActionCable for real-time updates (no AI cost)
- Share AI-generated suggestions across team members
- Implement conflict resolution without AI (deterministic algorithms)

### 3.2 Advanced Visual Tools
**Goal**: Support Figma imports and visual design tools

**Cost-Effective Approach**:
- Partner with existing visual-to-code tools
- Use SVG/CSS analysis instead of AI for simple designs
- Reserve AI for complex layout interpretation

## Cost Optimization Strategies

### 1. Caching and Pattern Recognition
```ruby
# Cache frequently requested generations
class AiResponseCache
  def self.get_or_generate(prompt_hash, &generator)
    Rails.cache.fetch("ai_response_#{prompt_hash}", expires_in: 7.days) do
      generator.call
    end
  end
end

# Usage
AiResponseCache.get_or_generate(Digest::MD5.hexdigest(prompt)) do
  OpenRouterClient.new.generate(prompt)
end
```

### 2. Prompt Optimization for Kimi-K2
```ruby
class PromptOptimizer
  # Kimi-K2 specific optimizations
  def self.optimize_for_kimi(base_prompt, context = {})
    # Research shows Kimi-K2 responds better to structured prompts
    structured_prompt = structure_prompt(base_prompt)
    add_context_efficiently(structured_prompt, context)
  end
  
  private
  
  def self.structure_prompt(prompt)
    # Format optimized for Kimi-K2's training
    <<~PROMPT
      Task: #{extract_task(prompt)}
      Context: #{extract_context(prompt)}
      Requirements: #{extract_requirements(prompt)}
      Expected Output: #{extract_output_format(prompt)}
    PROMPT
  end
end
```

### 3. Hybrid AI Strategy
```ruby
class HybridAiService
  def generate_code(complexity_level, prompt)
    case complexity_level
    when :simple
      # Use templates and patterns (no AI cost)
      TemplateEngine.generate(prompt)
    when :medium
      # Use Kimi-K2 (cost-effective)
      KimiK2Service.generate(prompt)
    when :complex
      # Use premium models sparingly
      ClaudeService.generate(prompt) if budget_allows?
    end
  end
  
  private
  
  def budget_allows?
    # Check monthly AI spending limits
    current_spending < monthly_budget * 0.8
  end
end
```

## Implementation Roadmap

### Month 1: Foundation
- [ ] Implement enhanced debugging assistant
- [ ] Create template system infrastructure
- [ ] Set up caching layer for AI responses
- [ ] Research Kimi-K2 multimodal capabilities

### Month 2: Core Tools
- [ ] Build multi-modal input processor
- [ ] Implement smart API integration assistant
- [ ] Create code suggestion engine
- [ ] Develop pattern recognition system

### Month 3: Advanced Features
- [ ] Add real-time collaboration basics
- [ ] Implement visual design analysis
- [ ] Create hybrid AI service architecture
- [ ] Launch premium tool features

## Cost Projections

### Current AI Costs (Kimi-K2 only):
- Estimated: $0.001 per 1K tokens (input), $0.002 per 1K tokens (output)
- Average app generation: ~50K tokens total
- Cost per app: ~$0.07-0.10

### With Enhanced Tools:
- Debugging assistance: +$0.01 per fix attempt
- Template modifications: +$0.02 per modification
- API integrations: +$0.03 per integration
- Visual analysis (when needed): +$0.20 per analysis (using premium models)

### Updated Cost Projections (1000 active users):
**Based on corrected Kimi-K2 pricing ($0.088/$0.088 per 1M tokens):**
- Current: ~$50-80/month (dramatically lower than projected)
- With Phase 1 tools: ~$120-180/month
- With Phase 2 tools: ~$200-300/month  
- With Phase 3 tools: ~$400-600/month

**Key cost advantages:**
- Average app generation now costs ~$0.009 (vs. $0.07-0.10 originally estimated)
- Debugging assistance: ~$0.001 per fix
- Template modifications: ~$0.002 per modification
- Tool calling workaround adds minimal cost due to efficient text parsing

## Success Metrics

### User Experience:
- Reduce app generation time by 40%
- Increase successful deployments by 60%
- Improve user satisfaction scores by 50%

### Technical:
- Maintain <2 second response time for tool interactions
- Achieve 90% cache hit rate for common patterns
- Keep AI costs under $1.50 per active user per month

### Business:
- Increase user retention by 35%
- Enable premium pricing tiers
- Reduce support tickets by 45%

## Risk Mitigation

### Cost Overruns:
- Implement hard spending limits per user
- Create cost monitoring dashboard
- Fall back to templates when budget exceeded

### AI Quality Issues:
- Maintain human review for critical generations
- Implement user feedback loops
- Create escalation paths for complex requests

### Competition:
- Focus on unique OverSkill features (deployment, marketplace)
- Leverage cost advantage of Kimi-K2
- Build strong community and template library

## Conclusion

By implementing these tools thoughtfully and leveraging Kimi-K2's cost efficiency, OverSkill can provide Lovable.dev-like capabilities while maintaining sustainable costs. The phased approach allows for gradual investment and learning, with clear metrics to guide decisions.

The key to success is balancing AI-powered features with smart caching, pattern recognition, and template systems to provide exceptional user experience without prohibitive costs.