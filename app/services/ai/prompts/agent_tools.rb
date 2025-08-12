# frozen_string_literal: true

require 'json'

module AI
  module Prompts
    class AgentTools
      # Default variable values
      DEFAULT_VARIABLES = {
        tool_prefix: "os-",
        platform_name: "OverSkill"
      }.freeze

      attr_reader :variables

      def initialize(variables = {})
        @variables = DEFAULT_VARIABLES.merge(variables)
      end

      # Generate the complete tools configuration with variables substituted
      def generate
        template = load_template
        substitute_variables(template)
      end

      # Generate tools config with custom variables (convenience method)
      def self.generate(variables = {})
        new(variables).generate
      end

      # Get parsed JSON configuration
      def parsed_config
        JSON.parse(generate)
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse agent tools JSON: #{e.message}"
        raise "Invalid JSON in agent tools configuration: #{e.message}"
      end

      # Get tool names from the configuration
      def tool_names
        parsed_config.map { |tool| tool["name"] }
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
        template_path = File.join(File.dirname(__FILE__), "agent-tools.json")
        File.read(template_path)
      rescue Errno::ENOENT => e
        Rails.logger.error "Agent tools template not found: #{e.message}"
        raise "Agent tools template file not found at #{template_path}"
      end

      def substitute_variables(template)
        result = template.dup

        resolved_variables.each do |key, value|
          placeholder = "{{#{key}}}"
          result.gsub!(placeholder, value.to_s)
        end

        # Remove the comment lines that contain variables documentation
        # as they're not valid JSON
        result = remove_json_comments(result)

        # Check for any remaining unsubstituted variables
        remaining_variables = result.scan(/\{\{([^}]+)\}\}/).flatten
        if remaining_variables.any?
          Rails.logger.warn "Unsubstituted variables in agent tools: #{remaining_variables.join(', ')}"
        end

        result
      end

      def remove_json_comments(json_string)
        # Remove JavaScript-style comments that aren't valid JSON
        lines = json_string.lines
        filtered_lines = lines.reject do |line|
          stripped = line.strip
          stripped.start_with?('//') || 
          (stripped.start_with?('/*') && stripped.end_with?('*/'))
        end
        filtered_lines.join
      end

      def resolved_variables
        @resolved_variables ||= variables.transform_values do |value|
          value.respond_to?(:call) ? value.call : value
        end
      end
    end
  end
end
