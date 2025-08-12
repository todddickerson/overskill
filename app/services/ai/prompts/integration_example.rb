# frozen_string_literal: true

# Example of integrating the Agent Prompt System with existing AI services
module AI
  module Prompts
    class IntegrationExample
      # Example: Using with AI App Generation
      class EnhancedAppBuilder
        def initialize(platform: :overskill, custom_variables: {})
          @prompt_service = AI::Prompts::AgentPromptService.for_platform(
            platform, 
            custom_variables
          )
        end

        def generate_app(user_prompt, app_name)
          system_prompt = @prompt_service.generate_prompt
          tools_config = @prompt_service.generate_tools
          
          # Simulate AI API call
          {
            system_prompt: system_prompt,
            tools: tools_config.map { |tool| tool["name"] },
            user_message: "Create an app called '#{app_name}': #{user_prompt}",
            metadata: {
              platform: @prompt_service.variables[:platform_name],
              generated_at: Time.current,
              tool_count: tools_config.size
            }
          }
        end
      end

      # Example: Dynamic configuration based on user/team
      class TeamSpecificPromptService
        def self.for_team(team)
          custom_variables = {
            platform_name: team.platform_name || "OverSkill",
            technology_stack: team.preferred_stack || "React, Vite, Tailwind CSS, and TypeScript",
            backend_integration: team.backend_preference || "Supabase",
            current_date: Date.current.strftime("%Y-%m-%d")
          }

          AI::Prompts::AgentPromptService.new(custom_variables)
        end

        def self.for_app_generation(app)
          team = app.team
          
          custom_variables = {
            platform_name: "#{team.name} Builder",
            tool_prefix: "#{team.slug}-",
            current_date: Date.current.strftime("%Y-%m-%d"),
            context_section_name: "app_context"
          }

          AI::Prompts::AgentPromptService.new(custom_variables)
        end
      end

      # Example: Background job integration
      class PromptGenerationJob < ApplicationJob
        def perform(team_id, config_type = :standard)
          team = Team.find(team_id)
          
          case config_type
          when :standard
            prompt_service = TeamSpecificPromptService.for_team(team)
          when :app_builder
            # Create a mock app for demonstration
            app = team.apps.first || team.apps.build(name: "Demo App")
            prompt_service = TeamSpecificPromptService.for_app_generation(app)
          else
            prompt_service = AI::Prompts::AgentPromptService.for_platform(:overskill)
          end

          config = prompt_service.generate_config
          
          # Store or cache the generated configuration
          Rails.cache.write(
            "team_#{team_id}_prompt_config_#{config_type}",
            config,
            expires_in: 1.hour
          )

          Rails.logger.info "Generated prompt config for team #{team_id} (#{config_type})"
          config
        end
      end

      # Example: API endpoint integration
      class PromptsController < ApplicationController
        def show
          platform = params[:platform]&.to_sym || :overskill
          
          unless AI::Prompts::AgentPromptService.available_platforms.include?(platform)
            return render json: { error: "Invalid platform" }, status: :bad_request
          end

          custom_vars = {
            current_date: Date.current.strftime("%Y-%m-%d")
          }

          # Add team-specific customizations if user is authenticated
          if current_user&.current_team
            custom_vars[:platform_name] = "#{current_user.current_team.name} AI"
          end

          prompt_service = AI::Prompts::AgentPromptService.for_platform(platform, custom_vars)
          
          if prompt_service.valid_config?
            config = prompt_service.generate_config
            render json: {
              prompt_length: config[:prompt].length,
              tool_count: config[:tools].size,
              tool_names: prompt_service.tool_names,
              platform: prompt_service.variables[:platform_name],
              generated_at: config[:metadata][:generated_at]
            }
          else
            render json: { 
              error: "Invalid configuration", 
              details: prompt_service.errors.full_messages 
            }, status: :unprocessable_entity
          end
        end

        def export
          platform = params[:platform]&.to_sym || :overskill
          prompt_service = AI::Prompts::AgentPromptService.for_platform(platform)
          
          export_path = prompt_service.export_to_files
          
          send_file File.join(export_path, "prompt.txt"), 
                   disposition: 'attachment',
                   filename: "#{platform}_agent_prompt.txt"
        end
      end

      # Example: Testing different configurations
      class ConfigurationTester
        def self.test_all_platforms
          results = {}
          
          AI::Prompts::AgentPromptService.available_platforms.each do |platform|
            begin
              service = AI::Prompts::AgentPromptService.for_platform(platform)
              config = service.generate_config
              
              results[platform] = {
                success: true,
                prompt_length: config[:prompt].length,
                tool_count: config[:tools].size,
                platform_name: service.variables[:platform_name],
                tool_prefix: service.variables[:tool_prefix]
              }
            rescue => e
              results[platform] = {
                success: false,
                error: e.message
              }
            end
          end
          
          results
        end

        def self.validate_variable_substitution
          test_vars = {
            platform_name: "TEST_PLATFORM",
            tool_prefix: "test_",
            current_date: "2025-01-01"
          }

          service = AI::Prompts::AgentPromptService.new(test_vars)
          prompt = service.generate_prompt
          tools = service.generate_tools

          issues = []
          issues << "Platform name not substituted" unless prompt.include?("TEST_PLATFORM")
          issues << "Tool prefix not substituted" unless tools.first["name"].start_with?("test_")
          issues << "Current date not substituted" unless prompt.include?("2025-01-01")
          
          remaining_vars = prompt.scan(/\{\{([^}]+)\}\}/).flatten
          issues << "Unsubstituted variables: #{remaining_vars.join(', ')}" if remaining_vars.any?

          {
            valid: issues.empty?,
            issues: issues,
            test_variables: test_vars
          }
        end
      end
    end
  end
end
