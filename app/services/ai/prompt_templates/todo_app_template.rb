module AI
  module PromptTemplates
    class TodoAppTemplate < BasePromptTemplate
      def self.enhance_user_prompt(user_prompt, options = {})
        <<~PROMPT
          Create a todo list application with the following requirements:
          
          USER REQUEST: #{user_prompt}
          
          CORE FEATURES TO INCLUDE:
          - Add new tasks with a clean input interface
          - Mark tasks as complete/incomplete with visual feedback
          - Delete tasks with confirmation
          - Edit existing tasks inline
          - Show task count and completion statistics
          - Persist data in localStorage
          - Responsive design that works on mobile
          
          OPTIONAL ENHANCEMENTS (include if mentioned by user or if it makes sense):
          - Categories or tags for tasks
          - Due dates with visual indicators
          - Priority levels (high, medium, low)
          - Search/filter functionality
          - Drag and drop to reorder
          - Dark mode toggle
          - Export tasks feature
          
          DESIGN REQUIREMENTS:
          - Clean, modern interface
          - Smooth animations for interactions
          - Clear visual hierarchy
          - Intuitive user experience
          - Professional color scheme
          - Accessible design (proper ARIA labels)
          
          Make sure the app feels polished and production-ready, not like a tutorial project.
        PROMPT
      end
    end
  end
end