module AI
  module PromptTemplates
    class CalculatorTemplate < BasePromptTemplate
      def self.enhance_user_prompt(user_prompt, options = {})
        <<~PROMPT
          Create a calculator application based on this request:
          
          USER REQUEST: #{user_prompt}
          
          CORE CALCULATOR FEATURES:
          - Number buttons (0-9) with proper layout
          - Basic operations (+, -, *, /)
          - Decimal point support
          - Clear (C) and Clear Entry (CE) buttons
          - Equals button for calculation
          - Display showing current number and result
          - Keyboard support for all operations
          
          OPTIONAL ENHANCEMENTS (include if mentioned or relevant):
          - Scientific calculator functions (sin, cos, tan, log, sqrt, etc.)
          - Memory functions (M+, M-, MR, MC)
          - History of calculations
          - Percentage calculations
          - Parentheses for order of operations
          - Theme switcher (light/dark mode)
          - Copy result to clipboard
          
          TECHNICAL REQUIREMENTS:
          - Accurate mathematical calculations
          - Handle edge cases (division by zero, overflow)
          - Responsive button feedback
          - Clear visual hierarchy
          - Smooth animations for button presses
          - Mobile-friendly touch targets
          - Accessibility features
          
          DESIGN REQUIREMENTS:
          - Clean, professional calculator interface
          - Large, easy-to-read display
          - Intuitive button layout
          - Visual feedback for operations
          - Modern design with subtle shadows/gradients
          
          The calculator should feel smooth and professional, like a native app.
        PROMPT
      end
    end
  end
end