# PuckToReactService - Converts PuckEditor visual configurations to React components
# Enables manual edit/tweak mode for AI-generated apps via drag-and-drop
# Part of the Fast Deployment Architecture for user customization
#
# Converts Puck's JSON structure to production React/TypeScript code

class PuckToReactService
  attr_reader :app

  # Component mapping from Puck types to React components
  COMPONENT_MAP = {
    "Button" => "Button",
    "Text" => "Typography",
    "Card" => "Card",
    "Image" => "Image",
    "Form" => "Form",
    "Input" => "Input",
    "Container" => "Container",
    "Grid" => "Grid",
    "Hero" => "HeroSection",
    "Features" => "FeaturesSection",
    "Pricing" => "PricingSection",
    "Navigation" => "Navigation",
    "Footer" => "Footer"
  }.freeze

  def initialize(app)
    @app = app
  end

  # Convert Puck configuration to React components
  def convert(puck_data, &block)
    Rails.logger.info "[PuckToReact] Converting Puck data for app #{app.id}"

    begin
      # Parse Puck configuration
      config = parse_puck_config(puck_data)

      # Generate React components
      components = generate_components(config)

      # Generate main App component
      app_component = generate_app_component(config)

      # Collect all generated files
      files = {}

      # Add main App.tsx
      files["src/App.tsx"] = app_component

      # Add individual components
      components.each do |name, content|
        files["src/components/#{name}.tsx"] = content
      end

      # Generate styles
      files["src/styles/puck-generated.css"] = generate_styles(config)

      # Update component index
      files["src/components/index.ts"] = generate_component_index(components.keys)

      Rails.logger.info "[PuckToReact] Generated #{files.size} files from Puck configuration"

      result = {
        success: true,
        files: files,
        components_count: components.size
      }

      block&.call(result)
      result
    rescue => e
      Rails.logger.error "[PuckToReact] Conversion failed: #{e.message}"
      error_result = {success: false, error: e.message}
      block&.call(error_result)
      error_result
    end
  end

  private

  def parse_puck_config(puck_data)
    # Parse Puck's JSON structure
    data = puck_data.is_a?(String) ? JSON.parse(puck_data) : puck_data

    {
      root: data["root"] || {},
      content: data["content"] || [],
      zones: data["zones"] || {},
      components: extract_components(data)
    }
  end

  def extract_components(data)
    components = []

    # Extract from root content
    if data["root"] && data["root"]["children"]
      components.concat(extract_components_recursive(data["root"]["children"]))
    end

    # Extract from zones
    data["zones"]&.each do |_zone_id, zone_content|
      components.concat(extract_components_recursive(zone_content))
    end

    components.uniq { |c| c["id"] }
  end

  def extract_components_recursive(items)
    return [] unless items.is_a?(Array)

    components = []

    items.each do |item|
      components << item if item["type"]

      # Recursively extract from children
      if item["props"] && item["props"]["children"]
        components.concat(extract_components_recursive(item["props"]["children"]))
      end
    end

    components
  end

  def generate_components(config)
    components = {}

    config[:components].each do |component_data|
      component_name = generate_component_name(component_data)
      component_code = generate_component_code(component_data)

      components[component_name] = component_code
    end

    components
  end

  def generate_component_name(component_data)
    base_name = COMPONENT_MAP[component_data["type"]] || component_data["type"]

    # Add unique suffix if needed
    if component_data["id"]
      "#{base_name}_#{component_data["id"].gsub(/[^a-zA-Z0-9]/, "")}"
    else
      base_name
    end
  end

  def generate_component_code(component_data)
    type = component_data["type"]
    props = component_data["props"] || {}

    # Generate TypeScript component based on type
    case type
    when "Button"
      generate_button_component(props)
    when "Text"
      generate_text_component(props)
    when "Card"
      generate_card_component(props)
    when "Container"
      generate_container_component(props)
    when "Hero"
      generate_hero_component(props)
    else
      generate_generic_component(type, props)
    end
  end

  def generate_button_component(props)
    <<~TSX
      import React from 'react';
      import { Button } from '@/components/ui/button';
      
      interface ButtonProps {
        onClick?: () => void;
        className?: string;
      }
      
      export const PuckButton: React.FC<ButtonProps> = ({ onClick, className }) => {
        return (
          <Button
            onClick={onClick}
            className={className}
            variant="#{props["variant"] || "default"}"
            size="#{props["size"] || "md"}"
          >
            #{props["text"] || "Click me"}
          </Button>
        );
      };
      
      export default PuckButton;
    TSX
  end

  def generate_text_component(props)
    <<~TSX
      import React from 'react';
      
      interface TextProps {
        className?: string;
      }
      
      export const PuckText: React.FC<TextProps> = ({ className }) => {
        return (
          <#{props["tag"] || "p"} className={className}>
            #{props["content"] || "Text content"}
          </#{props["tag"] || "p"}>
        );
      };
      
      export default PuckText;
    TSX
  end

  def generate_card_component(props)
    <<~TSX
      import React from 'react';
      import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
      
      interface CardProps {
        className?: string;
      }
      
      export const PuckCard: React.FC<CardProps> = ({ className }) => {
        return (
          <Card className={className}>
            <CardHeader>
              <CardTitle>#{props["title"] || "Card Title"}</CardTitle>
            </CardHeader>
            <CardContent>
              <p>#{props["content"] || "Card content goes here"}</p>
            </CardContent>
          </Card>
        );
      };
      
      export default PuckCard;
    TSX
  end

  def generate_container_component(props)
    <<~TSX
      import React from 'react';
      
      interface ContainerProps {
        children?: React.ReactNode;
        className?: string;
      }
      
      export const PuckContainer: React.FC<ContainerProps> = ({ children, className }) => {
        return (
          <div 
            className={`container mx-auto px-4 ${className || ''}`}
            style={{
              maxWidth: '#{props["maxWidth"] || "1200px"}',
              padding: '#{props["padding"] || "20px"}'
            }}
          >
            {children}
          </div>
        );
      };
      
      export default PuckContainer;
    TSX
  end

  def generate_hero_component(props)
    <<~TSX
      import React from 'react';
      import { Button } from '@/components/ui/button';
      
      interface HeroProps {
        className?: string;
      }
      
      export const PuckHero: React.FC<HeroProps> = ({ className }) => {
        return (
          <section className={`hero-section py-20 ${className || ''}`}>
            <div className="container mx-auto px-4 text-center">
              <h1 className="text-5xl font-bold mb-6">
                #{props["title"] || "Welcome to Our App"}
              </h1>
              <p className="text-xl mb-8 text-gray-600">
                #{props["subtitle"] || "Build something amazing"}
              </p>
              <div className="flex gap-4 justify-center">
                <Button size="lg" variant="default">
                  #{props["primaryButtonText"] || "Get Started"}
                </Button>
                <Button size="lg" variant="outline">
                  #{props["secondaryButtonText"] || "Learn More"}
                </Button>
              </div>
            </div>
          </section>
        );
      };
      
      export default PuckHero;
    TSX
  end

  def generate_generic_component(type, props)
    # Generate a generic component for unknown types
    <<~TSX
      import React from 'react';
      
      interface #{type}Props {
        className?: string;
        [key: string]: any;
      }
      
      export const Puck#{type}: React.FC<#{type}Props> = ({ className, ...props }) => {
        return (
          <div className={`puck-#{type.downcase} ${className || ''}`}>
            {/* Generated from Puck Editor */}
            <pre>{JSON.stringify(props, null, 2)}</pre>
          </div>
        );
      };
      
      export default Puck#{type};
    TSX
  end

  def generate_app_component(config)
    # Generate the main App component that renders the Puck layout
    imports = generate_imports(config[:components])
    layout = generate_layout(config)

    <<~TSX
      import React from 'react';
      #{imports}
      import './styles/puck-generated.css';
      
      function App() {
        return (
          <div className="puck-app">
            #{layout}
          </div>
        );
      }
      
      export default App;
    TSX
  end

  def generate_imports(components)
    components.map do |component|
      component_name = generate_component_name(component)
      "import { #{component_name} } from './components/#{component_name}';"
    end.join("\n")
  end

  def generate_layout(config)
    # Generate JSX layout from Puck configuration
    if config[:root] && config[:root]["children"]
      generate_jsx_recursive(config[:root]["children"])
    else
      "<div>No content</div>"
    end
  end

  def generate_jsx_recursive(items, indent = 6)
    return "" unless items.is_a?(Array)

    items.map do |item|
      component_name = generate_component_name(item)
      props_string = generate_props_string(item["props"] || {})
      children = item["props"] && item["props"]["children"]

      if children&.any?
        child_jsx = generate_jsx_recursive(children, indent + 2)
        "#{" " * indent}<#{component_name}#{props_string}>\n#{child_jsx}\n#{" " * indent}</#{component_name}>"
      else
        "#{" " * indent}<#{component_name}#{props_string} />"
      end
    end.join("\n")
  end

  def generate_props_string(props)
    return "" if props.empty?

    props_array = props.map do |key, value|
      next if key == "children"

      if value.is_a?(String)
        "#{key}=\"#{value}\""
      elsif value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
        "#{key}={#{value}}"
      else
        "#{key}={#{value.to_json}}"
      end
    end.compact

    props_array.empty? ? "" : " #{props_array.join(" ")}"
  end

  def generate_styles(config)
    # Generate CSS for Puck-generated components
    <<~CSS
      /* Puck Editor Generated Styles */
      
      .puck-app {
        min-height: 100vh;
        width: 100%;
      }
      
      .puck-container {
        width: 100%;
        max-width: var(--container-max-width, 1200px);
        margin: 0 auto;
        padding: var(--container-padding, 20px);
      }
      
      .hero-section {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
      }
      
      /* Component-specific styles */
      #{generate_component_styles(config[:components])}
      
      /* Responsive styles */
      @media (max-width: 768px) {
        .puck-container {
          padding: 15px;
        }
        
        .hero-section h1 {
          font-size: 2.5rem;
        }
      }
    CSS
  end

  def generate_component_styles(components)
    components.map do |component|
      type = component["type"].downcase
      styles = component["styles"] || {}

      if styles.any?
        ".puck-#{type} {\n" +
          styles.map { |k, v| "  #{k.tr("_", "-")}: #{v};" }.join("\n") +
          "\n}"
      end
    end.compact.join("\n\n")
  end

  def generate_component_index(component_names)
    # Generate index file for easy imports
    exports = component_names.map do |name|
      "export { default as #{name} } from './#{name}';"
    end.join("\n")

    <<~TS
      // Auto-generated component index from Puck Editor
      #{exports}
    TS
  end
end
