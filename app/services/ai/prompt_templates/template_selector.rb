module AI
  module PromptTemplates
    class TemplateSelector
      TEMPLATES = {
        todo: {
          keywords: %w[todo task list checklist planner organizer],
          class_name: "AI::PromptTemplates::TodoAppTemplate",
          name: "Todo List App"
        },
        game: {
          keywords: %w[game play score level puzzle arcade fun entertainment],
          class_name: "AI::PromptTemplates::GameTemplate",
          name: "Interactive Game"
        },
        landing: {
          keywords: %w[landing page website marketing site homepage product launch startup],
          class_name: "AI::PromptTemplates::LandingPageTemplate",
          name: "Landing Page"
        },
        dashboard: {
          keywords: %w[dashboard analytics data chart graph metrics kpi admin panel],
          class_name: "AI::PromptTemplates::DashboardTemplate",
          name: "Data Dashboard"
        },
        calculator: {
          keywords: %w[calculator calc calculate math arithmetic scientific],
          class_name: "AI::PromptTemplates::CalculatorTemplate",
          name: "Calculator App"
        }
      }

      def self.select_template(user_prompt, app_type = nil)
        # First check if app_type gives us a hint
        if app_type
          case app_type
          when "game"
            return TEMPLATES[:game]
          when "landing_page"
            return TEMPLATES[:landing]
          when "dashboard"
            return TEMPLATES[:dashboard]
          end
        end

        # Otherwise, analyze the prompt for keywords
        prompt_lower = user_prompt.downcase
        
        # Score each template based on keyword matches
        scores = {}
        
        TEMPLATES.each do |key, template|
          score = 0
          template[:keywords].each do |keyword|
            score += 1 if prompt_lower.include?(keyword)
          end
          scores[key] = score
        end
        
        # Get the template with highest score
        best_match = scores.max_by { |_, score| score }
        
        # Return the template if we found matches, otherwise return nil for base template
        if best_match[1] > 0
          TEMPLATES[best_match[0]]
        else
          nil
        end
      end

      def self.enhance_prompt(user_prompt, app_type = nil, framework = "vanilla")
        template_info = select_template(user_prompt, app_type)
        
        if template_info
          # Use specific template enhancement
          template_class = template_info[:class_name].constantize
          template_class.enhance_user_prompt(user_prompt)
        else
          # Use base template enhancement
          user_prompt
        end
      end

      def self.get_system_prompt(framework = "vanilla")
        BasePromptTemplate.system_prompt(framework)
      end
    end
  end
end