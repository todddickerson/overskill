module AI
  module Templates
    class TemplateRegistry
      TEMPLATES = {
        v1: {
          hello_world: {
            name: "Hello World",
            description: "Simple interactive app with customizable theme",
            class: HelloWorldTemplate,
            supports: ["vanilla", "react"]
          }
        },
        v2: {
          todo_list: {
            name: "Todo List",
            description: "Task management with add, edit, delete",
            class: nil, # TodoListTemplate (coming soon)
            supports: ["vanilla", "react", "vue"]
          },
          countdown_timer: {
            name: "Countdown Timer",  
            description: "Event countdown with notifications",
            class: nil, # CountdownTemplate
            supports: ["vanilla", "react"]
          },
          calculator: {
            name: "Calculator",
            description: "Basic arithmetic calculator",
            class: nil, # CalculatorTemplate
            supports: ["vanilla", "react"]
          }
        },
        v3: {
          landing_page: {
            name: "Landing Page",
            description: "Marketing page with sections and CTA",
            class: nil, # LandingPageTemplate
            supports: ["vanilla", "react", "nextjs"]
          },
          dashboard: {
            name: "Dashboard",
            description: "Data visualization dashboard",
            class: nil, # DashboardTemplate
            supports: ["react", "vue"]
          },
          blog: {
            name: "Blog",
            description: "Simple blog with posts",
            class: nil, # BlogTemplate
            supports: ["nextjs", "vanilla"]
          }
        }
      }

      def self.available_templates(version = :v1)
        TEMPLATES[version] || {}
      end

      def self.get_template(version, template_key)
        TEMPLATES.dig(version, template_key)
      end

      def self.template_exists?(version, template_key)
        TEMPLATES.dig(version, template_key, :class).present?
      end

      def self.supported_frameworks(version, template_key)
        TEMPLATES.dig(version, template_key, :supports) || []
      end

      def self.roadmap
        roadmap = {}
        
        TEMPLATES.each do |version, templates|
          roadmap[version] = templates.map do |key, template|
            {
              key: key,
              name: template[:name],
              description: template[:description],
              available: template[:class].present?,
              frameworks: template[:supports]
            }
          end
        end
        
        roadmap
      end
    end
  end
end