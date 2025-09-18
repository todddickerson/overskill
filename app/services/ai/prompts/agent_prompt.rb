# frozen_string_literal: true

module Ai
  module Prompts
    class AgentPrompt
      # Default variable values
      DEFAULT_VARIABLES = {
        current_date: -> { Date.current.strftime("%Y-%m-%d") },
        platform_name: "OverSkill",
        tool_prefix: "os-",
        technology_stack: "React, Vite, Tailwind CSS, and TypeScript",
        backend_integration: "Supabase",
        context_section_name: "useful-context"
      }.freeze

      attr_reader :variables

      def initialize(variables = {})
        @variables = DEFAULT_VARIABLES.merge(variables)
      end

      # Generate the complete prompt with variables substituted
      def generate
        template = load_template
        substitute_variables(template)
      end

      # Generate prompt with custom variables (convenience method)
      def self.generate(variables = {})
        new(variables).generate
      end

      # Get available variable names
      def self.available_variables
        DEFAULT_VARIABLES.keys
      end

      # Get the raw template without substitution
      def raw_template
        load_template
      end

      private

      def load_template
        template_path = ::File.join(::File.dirname(__FILE__), "agent-prompt.txt")
        ::File.read(template_path)
      rescue Errno::ENOENT => e
        Rails.logger.error "Agent prompt template not found: #{e.message}"
        raise "Agent prompt template file not found at #{template_path}"
      end

      def substitute_variables(template)
        result = template.dup

        resolved_variables.each do |key, value|
          placeholder = "{{#{key}}}"
          result.gsub!(placeholder, value.to_s)
        end

        # Check for any remaining unsubstituted variables
        remaining_variables = result.scan(/\{\{([^}]+)\}\}/).flatten
        if remaining_variables.any?
          Rails.logger.warn "Unsubstituted variables in agent prompt: #{remaining_variables.join(", ")}"
        end

        result
      end

      def resolved_variables
        @resolved_variables ||= variables.transform_values do |value|
          value.respond_to?(:call) ? value.call : value
        end
      end
    end
  end
end
