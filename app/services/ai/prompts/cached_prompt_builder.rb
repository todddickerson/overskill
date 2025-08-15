# frozen_string_literal: true

module Ai
  module Prompts
    # Builds optimized system prompts with Anthropic prompt caching
    # Based on: https://docs.anthropic.com/en/docs/build-with-claude/prompt-caching
    #
    # Key principles:
    # 1. Long-form data goes at the TOP of system prompt (20K+ tokens)
    # 2. Use cache_control on sections that don't change often
    # 3. System prompt as array enables multiple cache breakpoints
    # 4. Can have up to 4 cache breakpoints for different update frequencies
    class CachedPromptBuilder
      attr_reader :base_prompt, :template_files, :context_data
      
      def initialize(base_prompt:, template_files: [], context_data: {})
        @base_prompt = base_prompt
        @template_files = template_files
        @context_data = context_data
      end
      
      # Build system prompt array optimized for caching
      # Returns array format for Anthropic API with cache_control
      def build_system_prompt_array
        system_blocks = []
        
        # 1. LONG-FORM DATA FIRST (template files, existing code)
        # This is cached and reused across iterations
        if @template_files.any?
          template_content = build_template_files_content
          
          # Log cache decision for debugging
          Rails.logger.info "[CACHE] Template content size: #{template_content.length} chars, will cache: #{template_content.length > 5000}"
          
          if template_content.length > 5000  # Only cache if substantial
            system_blocks << {
              type: "text",
              text: template_content,
              cache_control: { type: "ephemeral" }  # Cache this heavy content
            }
          else
            system_blocks << {
              type: "text", 
              text: template_content
            }
          end
        end
        
        # 2. BASE AGENT PROMPT (changes rarely)
        # This contains the core instructions
        if @base_prompt.present?
          system_blocks << {
            type: "text",
            text: @base_prompt,
            cache_control: { type: "ephemeral" }  # Cache base instructions
          }
        end
        
        # 3. DYNAMIC CONTEXT (changes frequently)
        # Don't cache this as it updates each iteration
        if @context_data.any?
          context_content = build_useful_context
          system_blocks << {
            type: "text",
            text: context_content
            # No cache_control - this changes frequently
          }
        end
        
        system_blocks
      end
      
      # Build traditional single-string system prompt (fallback)
      def build_system_prompt_string
        parts = []
        
        # Same order: long-form data first
        parts << build_template_files_content if @template_files.any?
        parts << @base_prompt if @base_prompt.present?
        parts << build_useful_context if @context_data.any?
        
        parts.join("\n\n")
      end
      
      # Calculate token estimates for caching decisions
      def estimate_cache_savings
        template_tokens = estimate_tokens(build_template_files_content)
        base_prompt_tokens = estimate_tokens(@base_prompt)
        
        # With 90% savings on cached reads
        potential_savings = {
          template_files_tokens: template_tokens,
          base_prompt_tokens: base_prompt_tokens,
          total_cacheable_tokens: template_tokens + base_prompt_tokens,
          estimated_cost_reduction: 0.83  # 83% average reduction with caching
        }
      end
      
      private
      
      def build_template_files_content
        return "" if @template_files.empty?
        
        # Structure per documentation: wrap in XML tags for clarity
        <<~TEMPLATES
        <documents>
        #{format_template_files}
        </documents>
        
        INSTRUCTION: The above files are the existing template foundation. You can read and modify these files using the provided tools.
        TEMPLATES
      end
      
      def format_template_files
        @template_files.map.with_index do |file, index|
          # Use recommended document structure from docs
          # Add line numbers for consistent display with os-view/os-read
          numbered_content = file.content.to_s.lines.map.with_index(1) do |line, num|
            "#{num.to_s.rjust(4)}: #{line}"
          end.join.rstrip
          
          <<~DOC
          <document index="#{index + 1}">
            <source>#{file.path}</source>
            <document_content>
            ```#{detect_language(file.path)}
            #{numbered_content}
            ```
            </document_content>
          </document>
          DOC
        end.join("\n")
      end
      
      def build_useful_context
        return "" if @context_data.empty?
        
        # Dynamic context that changes frequently
        <<~CONTEXT
        
        <useful-context>
        #{format_context_data}
        </useful-context>
        CONTEXT
      end
      
      def format_context_data
        sections = []
        
        @context_data.each do |key, value|
          case key
          when :base_template_context
            # This already has "# useful-context" header from BaseContextService
            # Strip that header to avoid duplication
            cleaned_value = value.to_s.sub(/^# useful-context\n\n?/, '')
            sections << cleaned_value if cleaned_value.present?
          when :existing_files_context
            # This is pre-formatted existing files context
            sections << value if value.present?
          when :iteration_data
            sections << format_iteration_data(value)
          when :recent_operations
            sections << format_recent_operations(value)
          when :verification_results
            sections << format_verification_results(value)
          else
            sections << "### #{key.to_s.humanize}:\n#{value}"
          end
        end
        
        sections.compact.join("\n\n")
      end
      
      def format_iteration_data(data)
        <<~ITERATION
        ### Iteration #{data[:iteration]} of #{data[:max_iterations]}
        - Files generated: #{data[:files_generated]}
        - Last action: #{data[:last_action]}
        - Confidence: #{data[:confidence]}%
        ITERATION
      end
      
      def format_recent_operations(operations)
        return "### Recent Operations: None" if operations.blank?
        
        <<~OPS
        ### Recent Operations:
        #{operations.map { |op| "- #{op[:type]}: #{op[:description]}" }.join("\n")}
        OPS
      end
      
      def format_verification_results(results)
        return "" if results.blank?
        
        <<~VERIFY
        ### Verification Results:
        - Success: #{results[:success] ? 'Yes' : 'No'}
        - Confidence: #{results[:confidence]}%
        VERIFY
      end
      
      def detect_language(path)
        case ::File.extname(path)
        when '.ts', '.tsx' then 'typescript'
        when '.js', '.jsx' then 'javascript'
        when '.css' then 'css'
        when '.html' then 'html'
        when '.json' then 'json'
        when '.rb' then 'ruby'
        else 'text'
        end
      end
      
      def estimate_tokens(text)
        return 0 if text.blank?
        # Rough estimate: 1 token ≈ 4 characters
        (text.length / 4.0).ceil
      end
    end
  end
end