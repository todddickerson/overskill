module AI
  module PromptTemplates
    class DashboardTemplate < BasePromptTemplate
      def self.enhance_user_prompt(user_prompt, options = {})
        <<~PROMPT
          Create a data dashboard application based on this request:
          
          USER REQUEST: #{user_prompt}
          
          CORE DASHBOARD FEATURES:
          - Multiple data visualization widgets (charts, graphs, metrics)
          - Real-time or simulated data updates
          - Key performance indicators (KPIs) display
          - Interactive filters and date ranges
          - Responsive grid layout
          - Data tables with sorting/filtering
          - Export functionality for data/reports
          
          VISUALIZATION TYPES TO CONSIDER:
          - Line charts for trends
          - Bar/column charts for comparisons
          - Pie/donut charts for proportions
          - Number cards for key metrics
          - Progress indicators
          - Heat maps or geographic maps if relevant
          - Activity feeds or logs
          
          TECHNICAL REQUIREMENTS:
          - Use a charting library (Chart.js, D3.js, or similar via CDN)
          - Smooth animations for data updates
          - Loading states while fetching data
          - Error handling for data issues
          - Responsive design for all screen sizes
          - Dark/light theme toggle
          - Efficient data management
          
          The dashboard should look professional and provide genuine insights at a glance.
        PROMPT
      end
    end
  end
end