# frozen_string_literal: true

# Example usage of the Agent Prompt System
# Run this in Rails console: load Rails.root.join('app/services/ai/prompts/example_usage.rb')

module AI
  module Prompts
    class ExampleUsage
      def self.run_examples
        puts "=== AI Agent Prompt System Examples ==="
        puts

        # Basic usage
        basic_example

        # Custom variables
        custom_variables_example

        # Platform configurations
        platform_examples

        # Tools configuration
        tools_example

        # Export functionality
        export_example

        puts "=== All examples completed! ==="
      end

      private

      def self.basic_example
        puts "1. Basic Usage"
        puts "-" * 40

        service = AI::Prompts::AgentPromptService.new
        config = service.generate_config

        puts "Generated config with:"
        puts "  - Prompt: #{config[:prompt].length} characters"
        puts "  - Tools: #{config[:tools].size} tools"
        puts "  - Tool names: #{service.tool_names.first(3).join(', ')}..."
        puts "  - Platform: #{service.variables[:platform_name]}"
        puts
      end

      def self.custom_variables_example
        puts "2. Custom Variables"
        puts "-" * 40

        service = AI::Prompts::AgentPromptService.new(
          platform_name: "MyCustomPlatform",
          tool_prefix: "custom-",
          backend_integration: "Firebase",
          current_date: "2025-12-31"
        )

        prompt = service.generate_prompt
        puts "Custom platform name found: #{prompt.include?('MyCustomPlatform')}"
        puts "Custom tool prefix used: #{service.tool_names.first}"
        puts "Custom backend mentioned: #{prompt.include?('Firebase')}"
        puts
      end

      def self.platform_examples
        puts "3. Platform Configurations"
        puts "-" * 40

        platforms = AI::Prompts::AgentPromptService.available_platforms
        puts "Available platforms: #{platforms.join(', ')}"

        platforms.each do |platform|
          service = AI::Prompts::AgentPromptService.for_platform(platform)
          puts "  #{platform}: #{service.variables[:platform_name]} (#{service.variables[:tool_prefix]})"
        end
        puts
      end

      def self.tools_example
        puts "4. Tools Configuration"
        puts "-" * 40

        service = AI::Prompts::AgentPromptService.new
        tools = service.generate_tools

        puts "Total tools: #{tools.size}"
        puts "Sample tool names:"
        service.tool_names.first(5).each do |name|
          puts "  - #{name}"
        end

        # Show first tool structure
        first_tool = tools.first
        puts "\nFirst tool structure:"
        puts "  Name: #{first_tool['name']}"
        puts "  Description: #{first_tool['description'][0..80]}..."
        puts
      end

      def self.export_example
        puts "5. Export Functionality"
        puts "-" * 40

        service = AI::Prompts::AgentPromptService.new(
          platform_name: "ExportTest",
          current_date: Date.current.strftime("%Y-%m-%d")
        )

        begin
          export_path = service.export_to_files(Rails.root.join("tmp", "example_export"))
          puts "Exported to: #{export_path}"
          
          files = Dir.glob(File.join(export_path, "*"))
          puts "Created files:"
          files.each do |file|
            size = File.size(file)
            puts "  - #{File.basename(file)} (#{size} bytes)"
          end
        rescue => e
          puts "Export failed: #{e.message}"
        end
        puts
      end
    end
  end
end

# Uncomment to run examples automatically
# AI::Prompts::ExampleUsage.run_examples
