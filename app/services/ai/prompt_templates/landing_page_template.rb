module AI
  module PromptTemplates
    class LandingPageTemplate < BasePromptTemplate
      def self.enhance_user_prompt(user_prompt, options = {})
        <<~PROMPT
          Create a modern landing page based on this request:
          
          USER REQUEST: #{user_prompt}
          
          REQUIRED SECTIONS:
          - Hero section with compelling headline and call-to-action
          - Features/Benefits section with icons or illustrations
          - Social proof (testimonials, logos, or stats)
          - Pricing or product information
          - Contact or sign-up form
          - Footer with links and information
          
          DESIGN REQUIREMENTS:
          - Modern, professional design
          - Smooth scroll animations
          - Mobile-first responsive layout
          - Fast loading and optimized
          - SEO-friendly structure
          - Engaging micro-interactions
          - Consistent brand colors throughout
          
          TECHNICAL FEATURES:
          - Smooth scrolling navigation
          - Form validation and submission handling
          - Loading states for interactions
          - Accessibility compliant
          - Cross-browser compatible
          - Performance optimized
          
          The landing page should feel premium and convert visitors into customers/users.
        PROMPT
      end
    end
  end
end