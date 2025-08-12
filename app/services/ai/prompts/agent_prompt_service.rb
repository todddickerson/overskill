# frozen_string_literal: true

module AI
  module Prompts
    class AgentPromptService
      include ActiveModel::Validations

      attr_reader :variables, :prompt_generator, :tools_generator

      validates :variables, presence: true
      validate :validate_required_variables

      def initialize(variables = {})
        @variables = default_variables.merge(variables)
        @prompt_generator = AgentPrompt.new(@variables)
        @tools_generator = AgentTools.new(@variables)
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

      # Generate just the prompt
      def generate_prompt
        prompt_generator.generate
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

      # Export configuration to files (for debugging/inspection)
      def export_to_files(base_path = Rails.root.join("tmp", "agent_config"))
        FileUtils.mkdir_p(base_path)
        
        config = generate_config
        
        File.write(File.join(base_path, "prompt.txt"), config[:prompt])
        File.write(File.join(base_path, "tools.json"), JSON.pretty_generate(config[:tools]))
        File.write(File.join(base_path, "metadata.json"), JSON.pretty_generate(config[:metadata]))
        
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
          context_section_name: "additional_data"
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

      # Platform-specific configurations
      def self.platform_configurations
        {
          overskill: {
            platform_name: "OverSkill",
            tool_prefix: "os-",
            technology_stack: "React, Vite, Tailwind CSS, and TypeScript",
            backend_integration: "Supabase",
            context_section_name: "additional_data"
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
