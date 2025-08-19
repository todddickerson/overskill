# frozen_string_literal: true

module Ai
  module Prompts
    class AgentPromptService
      include ActiveModel::Validations

      attr_reader :variables, :prompt_generator, :tools_generator, :context_data

      validates :variables, presence: true
      validate :validate_required_variables

      def initialize(variables = {})
        @variables = default_variables.merge(variables)
        @prompt_generator = AgentPrompt.new(@variables)
        @tools_generator = AgentTools.new(@variables)
        @context_data = {}
      end

      # Generate complete agent configuration
      def generate_config
        {
          prompt: prompt_generator.generate,
          tools: tools_generator.parsed_config,
          metadata: {
            generated_at: Time.current.iso8601,
            variables_used: variables,
            tool_count: tools_generator.tool_names.size,
            tool_names: tools_generator.tool_names
          }
        }
      end

      # Generate just the prompt with optional context
      def generate_prompt(include_context: true)
        base_prompt = prompt_generator.generate
        
        if include_context && @context_data.any?
          base_prompt + generate_useful_context
        else
          base_prompt
        end
      end

      # Generate just the tools configuration
      def generate_tools
        tools_generator.parsed_config
      end

      # Get list of available tool names
      def tool_names
        tools_generator.tool_names
      end

      # Validate that all required variables are present and valid
      def valid_config?
        valid? && validate_templates
      end

      # Generate configuration for specific platform
      def self.for_platform(platform_name, custom_variables = {})
        platform_config = platform_configurations[platform_name.to_sym] || {}
        variables = platform_config.merge(custom_variables)
        new(variables)
      end

      # Get all available platforms
      def self.available_platforms
        platform_configurations.keys
      end

      # Add context data that will be included in the prompt
      def add_context(key, value)
        @context_data[key] = value
        self
      end
      
      # Add console logs to context
      def add_console_logs(logs)
        add_context(:console_logs, logs) if logs.present?
      end
      
      # Add network requests to context
      def add_network_requests(requests)
        add_context(:network_requests, requests) if requests.present?
      end
      
      # Add current files to context
      def add_current_files(files)
        return unless files.present?
        
        files_context = files.map do |file|
          <<~FILE
          ## File: #{file.path}
          ```#{file.language || detect_language(file.path)}
          #{file.content}
          ```
          FILE
        end.join("\n")
        
        add_context(:current_files, files_context)
      end
      
      # Add project structure to context
      def add_project_structure(structure)
        add_context(:project_structure, structure) if structure.present?
      end
      
      # Add Git status to context
      def add_git_status(status)
        add_context(:git_status, status) if status.present?
      end
      
      # Generate iteration-specific context for agent loop
      def generate_iteration_context(iteration_data)
        <<~ITERATION
        
        ## AGENT LOOP ITERATION #{iteration_data[:iteration]} OF #{iteration_data[:max_iterations]}
        
        ### CURRENT GOALS STATUS:
        - Total Goals: #{iteration_data[:goals][:total_goals]}
        - Completed: #{iteration_data[:goals][:completed]} (#{iteration_data[:goals][:completion_percentage]}%)
        - Remaining: #{iteration_data[:goals][:remaining]}
        - Next Priority: #{iteration_data[:goals][:next_priority_goal]&.dig(:description) || 'None'}
        
        ### PREVIOUS ACTIONS TAKEN:
        #{format_previous_actions(iteration_data[:history])}
        
        ### GENERATED FILES SO FAR:
        #{format_generated_files(iteration_data[:generated_files])}
        
        ### CURRENT CONTEXT COMPLETENESS: #{iteration_data[:context_completeness]}%
        
        ### LAST VERIFICATION RESULTS:
        #{format_verification_results(iteration_data[:verification_results]&.last)}
        
        ### INSTRUCTION:
        Continue working towards completing all goals. Focus on what still needs to be done.
        Based on the above context, determine your next action. You MUST respond with one of these action types:
        - GATHER_CONTEXT: if you need more information
        - PLAN_IMPLEMENTATION: if ready to create an implementation plan  
        - EXECUTE_TOOLS: if ready to make code changes  
        - VERIFY_CHANGES: if you need to check your previous work
        - DEBUG_ISSUES: if there are errors to fix
        - REQUEST_FEEDBACK: if user input is needed
        - COMPLETE_TASK: if all goals are achieved
        
        Start your response with "ACTION_TYPE: [type]" followed by your reasoning and implementation.
        ITERATION
      end
      
      # Export configuration to files (for debugging/inspection)
      def export_to_files(base_path = Rails.root.join("tmp", "agent_config"))
        FileUtils.mkdir_p(base_path)
        
        config = generate_config
        
        ::File.write(::File.join(base_path, "prompt.txt"), config[:prompt])
        ::File.write(::File.join(base_path, "tools.json"), JSON.pretty_generate(config[:tools]))
        ::File.write(::File.join(base_path, "metadata.json"), JSON.pretty_generate(config[:metadata]))
        
        Rails.logger.info "Agent configuration exported to #{base_path}"
        base_path
      end

      private

      def default_variables
        {
          current_date: Date.current.strftime("%Y-%m-%d"),
          platform_name: "OverSkill",
          tool_prefix: "os-",
          technology_stack: "React, Vite, Tailwind CSS, and TypeScript",
          backend_integration: "Supabase",
          context_section_name: "useful-context"
        }
      end

      def validate_required_variables
        required_keys = [:platform_name, :tool_prefix, :current_date]
        
        required_keys.each do |key|
          if variables[key].blank?
            errors.add(:variables, "#{key} is required")
          end
        end
      end

      def validate_templates
        begin
          prompt_generator.generate
          tools_generator.parsed_config
          true
        rescue => e
          Rails.logger.error "Template validation failed: #{e.message}"
          errors.add(:base, "Template validation failed: #{e.message}")
          false
        end
      end

      # Generate the useful-context section
      def generate_useful_context
        return "" if @context_data.empty?
        
        <<~CONTEXT
        
        <useful-context>
        # Context Information
        
        #{format_context_data}
        </useful-context>
        CONTEXT
      end
      
      def format_context_data
        @context_data.map do |key, value|
          case key
          when :console_logs
            format_console_logs(value)
          when :network_requests
            format_network_requests(value)
          when :current_files
            "### Current Files in Context:\n#{value}"
          when :project_structure
            "### Project Structure:\n```\n#{value}\n```"
          when :git_status
            "### Git Status:\n```\n#{value}\n```"
          else
            "### #{key.to_s.humanize}:\n#{value}"
          end
        end.join("\n\n")
      end
      
      def format_console_logs(logs)
        return "### Console Logs:\nNo recent console logs" if logs.blank?
        
        <<~LOGS
        ### Console Logs (Recent):
        ```
        #{logs}
        ```
        LOGS
      end
      
      def format_network_requests(requests)
        return "### Network Requests:\nNo recent network requests" if requests.blank?
        
        <<~REQUESTS
        ### Network Requests (Recent):
        ```
        #{requests}
        ```
        REQUESTS
      end
      
      def format_previous_actions(history)
        return "No previous actions" if history.blank?
        
        history.last(3).map.with_index do |h, i|
          "#{i + 1}. Iteration #{h[:iteration]}: #{h[:action][:type]} - #{h[:verification][:success] ? '✓ Success' : '✗ Failed'}"
        end.join("\n")
      end
      
      def format_generated_files(files)
        return "No files generated yet" if files.blank?
        
        files.map { |f| f.respond_to?(:path) ? f.path : f }.join("\n")
      end
      
      def format_verification_results(results)
        return "No verification results yet" if results.blank?
        
        <<~VERIFY
        - Success: #{results[:success] ? 'Yes' : 'No'}
        - Confidence: #{(results[:confidence] * 100).to_i}%
        #{results[:errors].present? ? "- Errors: #{results[:errors].join(', ')}" : ""}
        VERIFY
      end
      
      def detect_language(path)
        case ::File.extname(path)
        when '.ts', '.tsx'
          'typescript'
        when '.js', '.jsx'
          'javascript'
        when '.css'
          'css'
        when '.html'
          'html'
        when '.json'
          'json'
        when '.rb'
          'ruby'
        when '.yml', '.yaml'
          'yaml'
        else
          'text'
        end
      end
      
      # Platform-specific configurations
      def self.platform_configurations
        {
          overskill: {
            platform_name: "OverSkill",
            tool_prefix: "os-",
            technology_stack: "React, Vite, Tailwind CSS, and TypeScript",
            backend_integration: "Supabase Shared",
            context_section_name: "useful-context"
          },
          lovable: {
            platform_name: "Lovable",
            tool_prefix: "lov-",
            technology_stack: "React, Vite, Tailwind CSS, and TypeScript",
            backend_integration: "Supabase",
            context_section_name: "useful-context"
          },
          generic: {
            platform_name: "AI Code Assistant",
            tool_prefix: "ai-",
            technology_stack: "Modern Web Technologies",
            backend_integration: "Cloud Services",
            context_section_name: "context"
          }
        }
      end
    end
  end
end
