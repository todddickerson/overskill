module AI
  module PromptTemplates
    class GameTemplate < BasePromptTemplate
      def self.enhance_user_prompt(user_prompt, options = {})
        <<~PROMPT
          Create an interactive web game based on this request:
          
          USER REQUEST: #{user_prompt}
          
          CORE GAME FEATURES:
          - Clear game objective and rules
          - Interactive controls (keyboard, mouse, or touch)
          - Score tracking system
          - Game state management (start, playing, pause, game over)
          - Progressive difficulty or levels
          - Visual and audio feedback for actions
          - High score tracking (localStorage)
          
          TECHNICAL REQUIREMENTS:
          - Smooth animations (60 FPS target)
          - Responsive controls with no lag
          - Mobile-friendly touch controls
          - Pause/resume functionality
          - Sound effects (with mute option)
          - Proper game loop implementation
          - Collision detection if needed
          
          UI/UX REQUIREMENTS:
          - Attractive game graphics (can use CSS, Canvas, or SVG)
          - Clear UI for score, lives, level, etc.
          - Start screen with instructions
          - Game over screen with replay option
          - Smooth transitions between states
          - Fun and engaging visual style
          
          The game should be addictive, polished, and fun to play repeatedly.
        PROMPT
      end
    end
  end
end