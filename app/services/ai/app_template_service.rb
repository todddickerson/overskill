module Ai
  # Service for providing app templates and accelerating AI generation
  # Templates reduce generation time and ensure consistent quality
  class AppTemplateService
    # Common app templates that can be quickly customized
    TEMPLATES = {
      dashboard: {
        name: "Dashboard App",
        description: "Modern dashboard with charts, tables, and analytics",
        category: "business",
        files: {
          "index.html" => :dashboard_html,
          "src/App.tsx" => :dashboard_app,
          "src/components/Dashboard.tsx" => :dashboard_component,
          "src/components/Chart.tsx" => :chart_component,
          "src/hooks/useData.ts" => :data_hook,
          "src/styles.css" => :dashboard_styles
        }
      },

      landing_page: {
        name: "Landing Page",
        description: "Professional landing page with hero, features, and CTA",
        category: "marketing",
        files: {
          "index.html" => :landing_html,
          "src/App.tsx" => :landing_app,
          "src/components/Hero.tsx" => :hero_component,
          "src/components/Features.tsx" => :features_component,
          "src/components/CTA.tsx" => :cta_component,
          "src/styles.css" => :landing_styles
        }
      },

      saas_tool: {
        name: "SaaS Tool",
        description: "Complete SaaS application with auth, billing, and features",
        category: "saas",
        files: {
          "index.html" => :saas_html,
          "src/App.tsx" => :saas_app,
          "src/components/Layout.tsx" => :layout_component,
          "src/components/Sidebar.tsx" => :sidebar_component,
          "src/pages/Dashboard.tsx" => :dashboard_page,
          "src/pages/Settings.tsx" => :settings_page,
          "src/hooks/useAuth.ts" => :auth_hook,
          "src/services/api.ts" => :api_service,
          "src/styles.css" => :saas_styles
        }
      },

      game: {
        name: "Simple Game",
        description: "Interactive game with canvas and game logic",
        category: "game",
        files: {
          "index.html" => :game_html,
          "src/App.tsx" => :game_app,
          "src/components/GameCanvas.tsx" => :game_canvas,
          "src/components/GameControls.tsx" => :game_controls,
          "src/game/GameEngine.ts" => :game_engine,
          "src/styles.css" => :game_styles
        }
      }
    }.freeze

    def initialize
      @templates = TEMPLATES
    end

    # Get template by key
    def get_template(template_key)
      template = @templates[template_key.to_sym]
      return nil unless template

      {
        name: template[:name],
        description: template[:description],
        category: template[:category],
        files: generate_template_files(template[:files])
      }
    end

    # Get all available templates
    def all_templates
      @templates.map do |key, template|
        {
          key: key,
          name: template[:name],
          description: template[:description],
          category: template[:category]
        }
      end
    end

    # Generate template-enhanced prompt for AI
    def enhance_prompt_with_template(user_prompt, template_key = nil)
      # Auto-detect template if not provided
      template_key ||= detect_template_from_prompt(user_prompt)

      if template_key
        template = get_template(template_key)
        return <<~PROMPT
          #{user_prompt}
          
          BASE TEMPLATE: Use the "#{template[:name]}" template as a starting point.
          
          TEMPLATE STRUCTURE:
          #{template[:files].keys.map { |path| "- #{path}" }.join("\n")}
          
          CUSTOMIZATION INSTRUCTIONS:
          - Keep the proven template structure but customize content, styling, and functionality
          - Maintain professional code quality and modern React patterns
          - Ensure all template components are properly integrated
          - Add requested features while preserving template foundation
        PROMPT
      end

      user_prompt
    end

    private

    def generate_template_files(file_map)
      files = {}

      file_map.each do |path, template_method|
        files[path] = send(template_method)
      end

      files
    end

    def detect_template_from_prompt(prompt)
      prompt_lower = prompt.downcase

      return :dashboard if prompt_lower.match?(/dashboard|analytics|chart|metrics|admin/)
      return :landing_page if prompt_lower.match?(/landing|homepage|website|marketing/)
      return :saas_tool if prompt_lower.match?(/saas|subscription|billing|account|settings/)
      return :game if prompt_lower.match?(/game|play|canvas|score|level/)

      nil
    end

    # Template file contents

    def dashboard_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Dashboard</title>
          <script src="https://cdn.tailwindcss.com"></script>
        </head>
        <body>
          <div id="root"></div>
        </body>
        </html>
      HTML
    end

    def dashboard_app
      <<~TSX
        import React from 'react';
        import Dashboard from './components/Dashboard';
        
        function App() {
          return (
            <div className="min-h-screen bg-gray-50">
              <Dashboard />
            </div>
          );
        }
        
        export default App;
      TSX
    end

    def dashboard_component
      <<~TSX
        import React from 'react';
        import Chart from './Chart';
        import { useData } from '../hooks/useData';
        
        export default function Dashboard() {
          const { data, loading } = useData();
          
          if (loading) {
            return <div className="p-8">Loading...</div>;
          }
          
          return (
            <div className="p-8">
              <h1 className="text-3xl font-bold text-gray-900 mb-8">Dashboard</h1>
              
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
                <div className="bg-white p-6 rounded-lg shadow">
                  <h3 className="text-sm font-medium text-gray-500">Total Users</h3>
                  <p className="text-2xl font-bold text-gray-900">{data.totalUsers}</p>
                </div>
                
                <div className="bg-white p-6 rounded-lg shadow">
                  <h3 className="text-sm font-medium text-gray-500">Revenue</h3>
                  <p className="text-2xl font-bold text-gray-900">${data.revenue}</p>
                </div>
                
                <div className="bg-white p-6 rounded-lg shadow">
                  <h3 className="text-sm font-medium text-gray-500">Growth</h3>
                  <p className="text-2xl font-bold text-green-600">+{data.growth}%</p>
                </div>
                
                <div className="bg-white p-6 rounded-lg shadow">
                  <h3 className="text-sm font-medium text-gray-500">Active Now</h3>
                  <p className="text-2xl font-bold text-gray-900">{data.activeNow}</p>
                </div>
              </div>
              
              <div className="bg-white p-6 rounded-lg shadow">
                <h2 className="text-lg font-semibold mb-4">Analytics</h2>
                <Chart data={data.chartData} />
              </div>
            </div>
          );
        }
      TSX
    end

    def chart_component
      <<~TSX
        import React from 'react';
        
        interface ChartProps {
          data: number[];
        }
        
        export default function Chart({ data }: ChartProps) {
          const maxValue = Math.max(...data);
          
          return (
            <div className="flex items-end space-x-2 h-40">
              {data.map((value, index) => (
                <div
                  key={index}
                  className="bg-blue-500 rounded-t"
                  style={{
                    height: `${(value / maxValue) * 100}%`,
                    width: '20px'
                  }}
                />
              ))}
            </div>
          );
        }
      TSX
    end

    def data_hook
      <<~TS
        import { useState, useEffect } from 'react';
        
        interface DashboardData {
          totalUsers: number;
          revenue: number;
          growth: number;
          activeNow: number;
          chartData: number[];
        }
        
        export function useData() {
          const [data, setData] = useState<DashboardData | null>(null);
          const [loading, setLoading] = useState(true);
          
          useEffect(() => {
            // Simulate API call
            setTimeout(() => {
              setData({
                totalUsers: 12543,
                revenue: 45231,
                growth: 12.5,
                activeNow: 234,
                chartData: [12, 19, 3, 5, 2, 3, 20, 15, 10, 8, 12, 25]
              });
              setLoading(false);
            }, 1000);
          }, []);
          
          return { data, loading };
        }
      TS
    end

    def dashboard_styles
      <<~CSS
        /* Dashboard specific styles */
        .dashboard-card {
          @apply bg-white rounded-lg shadow-sm border border-gray-200 p-6;
        }
        
        .metric-card {
          @apply bg-white rounded-lg shadow-sm p-6 border border-gray-200;
        }
        
        .chart-container {
          @apply bg-white rounded-lg shadow-sm p-6;
        }
      CSS
    end

    def landing_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Landing Page</title>
          <script src="https://cdn.tailwindcss.com"></script>
        </head>
        <body>
          <div id="root"></div>
        </body>
        </html>
      HTML
    end

    def landing_app
      <<~TSX
        import React from 'react';
        import Hero from './components/Hero';
        import Features from './components/Features';
        import CTA from './components/CTA';
        
        function App() {
          return (
            <div className="min-h-screen bg-white">
              <Hero />
              <Features />
              <CTA />
            </div>
          );
        }
        
        export default App;
      TSX
    end

    def hero_component
      <<~TSX
        import React from 'react';
        
        export default function Hero() {
          return (
            <div className="bg-gradient-to-r from-blue-600 to-purple-600 text-white">
              <div className="max-w-7xl mx-auto px-4 py-20">
                <div className="text-center">
                  <h1 className="text-5xl font-bold mb-6">
                    Welcome to Our Platform
                  </h1>
                  <p className="text-xl mb-8 max-w-2xl mx-auto">
                    Transform your business with our innovative solution. 
                    Get started today and see the difference.
                  </p>
                  <button className="bg-white text-blue-600 px-8 py-3 rounded-lg font-semibold text-lg hover:bg-gray-50 transition-colors">
                    Get Started Free
                  </button>
                </div>
              </div>
            </div>
          );
        }
      TSX
    end

    def features_component
      <<~TSX
        import React from 'react';
        
        export default function Features() {
          const features = [
            {
              title: "Fast & Reliable",
              description: "Lightning-fast performance with 99.9% uptime guarantee."
            },
            {
              title: "Easy to Use",
              description: "Intuitive interface that anyone can master in minutes."
            },
            {
              title: "Secure",
              description: "Enterprise-grade security to protect your data."
            }
          ];
          
          return (
            <div className="py-20 bg-gray-50">
              <div className="max-w-7xl mx-auto px-4">
                <div className="text-center mb-16">
                  <h2 className="text-3xl font-bold text-gray-900 mb-4">
                    Why Choose Us?
                  </h2>
                  <p className="text-lg text-gray-600">
                    Everything you need to succeed, all in one place.
                  </p>
                </div>
                
                <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
                  {features.map((feature, index) => (
                    <div key={index} className="text-center">
                      <h3 className="text-xl font-semibold text-gray-900 mb-4">
                        {feature.title}
                      </h3>
                      <p className="text-gray-600">
                        {feature.description}
                      </p>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          );
        }
      TSX
    end

    def cta_component
      <<~TSX
        import React from 'react';
        
        export default function CTA() {
          return (
            <div className="bg-blue-600 text-white py-20">
              <div className="max-w-4xl mx-auto px-4 text-center">
                <h2 className="text-3xl font-bold mb-4">
                  Ready to Get Started?
                </h2>
                <p className="text-xl mb-8">
                  Join thousands of satisfied customers today.
                </p>
                <button className="bg-white text-blue-600 px-8 py-3 rounded-lg font-semibold text-lg hover:bg-gray-50 transition-colors mr-4">
                  Start Free Trial
                </button>
                <button className="border border-white text-white px-8 py-3 rounded-lg font-semibold text-lg hover:bg-white hover:text-blue-600 transition-colors">
                  Learn More
                </button>
              </div>
            </div>
          );
        }
      TSX
    end

    def landing_styles
      <<~CSS
        /* Landing page specific styles */
        .hero-gradient {
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }
        
        .feature-card {
          @apply bg-white p-6 rounded-lg shadow-sm border border-gray-200;
        }
        
        .cta-button {
          @apply bg-blue-600 text-white px-6 py-3 rounded-lg font-medium hover:bg-blue-700 transition-colors;
        }
      CSS
    end

    # Additional template methods would be defined here...
    # For brevity, I'm showing the pattern with dashboard and landing page templates
  end
end
