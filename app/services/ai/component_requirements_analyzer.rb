module Ai
  # Analyzes user requirements to determine required components upfront
  # This prevents missing import errors by pre-determining what will be needed
  class ComponentRequirementsAnalyzer
    
    # Common app patterns and their required components/icons
    APP_PATTERNS = {
      'landing' => {
        icons: %w[Menu X ChevronDown ArrowRight Check Star Zap Crown Shield Lock Globe Mail Phone MapPin],
        shadcn: %w[button card badge accordion tabs dialog sheet],
        sections: %w[HeroSection FeaturesSection PricingSection CTASection FAQSection TestimonialsSection]
      },
      'saas' => {
        icons: %w[Menu X Check Shield Lock CreditCard DollarSign Zap Crown Rocket Star Award Trophy TrendingUp],
        shadcn: %w[button card badge tabs dialog sheet toast alert],
        sections: %w[HeroSection FeaturesSection PricingSection CTASection FAQSection SocialProofSection]
      },
      'dashboard' => {
        icons: %w[Menu X Home User Users Settings Bell Search Filter Calendar ChevronDown ChevronRight BarChart TrendingUp],
        shadcn: %w[button card badge tabs dialog sheet select dropdown-menu avatar],
        sections: %w[Sidebar Header StatsCards RecentActivity]
      },
      'todo' => {
        icons: %w[Plus Trash Edit Check X Circle CheckCircle Clock Calendar Filter],
        shadcn: %w[button card checkbox input label dialog sheet],
        sections: %w[TaskList TaskForm TaskFilters]
      },
      'ecommerce' => {
        icons: %w[ShoppingCart Package CreditCard Heart Star Search Filter ChevronDown Plus Minus],
        shadcn: %w[button card badge dialog sheet select input],
        sections: %w[ProductGrid ProductCard CartDrawer CheckoutForm]
      },
      'blog' => {
        icons: %w[Calendar Clock User Tag Share Heart Bookmark ArrowRight],
        shadcn: %w[button card badge avatar],
        sections: %w[BlogList BlogCard BlogPost AuthorBio]
      },
      'portfolio' => {
        icons: %w[Github Linkedin Twitter Mail Globe ExternalLink ArrowRight],
        shadcn: %w[button card badge tabs],
        sections: %w[HeroSection ProjectsGrid AboutSection ContactForm]
      },
      'chat' => {
        icons: %w[Send User Users Plus Paperclip Smile Phone Video Settings],
        shadcn: %w[button card input avatar scroll-area],
        sections: %w[ChatList MessageThread MessageInput UserList]
      },
      'form' => {
        icons: %w[Check X AlertCircle Info Upload],
        shadcn: %w[button card input label select checkbox radio-group textarea form],
        sections: %w[FormContainer FormFields ValidationMessages]
      },
      'analytics' => {
        icons: %w[TrendingUp TrendingDown BarChart LineChart PieChart Download Filter Calendar],
        shadcn: %w[button card select date-picker tabs],
        sections: %w[MetricsCards ChartsGrid DataTable DateRangePicker]
      }
    }
    
    # Keywords that trigger specific component requirements
    KEYWORD_TRIGGERS = {
      'payment' => { icons: %w[CreditCard DollarSign Shield Lock], shadcn: %w[form input] },
      'auth' => { icons: %w[User Lock Mail Key], shadcn: %w[form input button] },
      'social' => { icons: %w[Github Twitter Linkedin Facebook Instagram Youtube], shadcn: %w[button] },
      'upload' => { icons: %w[Upload Cloud File Image], shadcn: %w[button dialog] },
      'search' => { icons: %w[Search Filter X], shadcn: %w[input button] },
      'notification' => { icons: %w[Bell Mail AlertCircle Check], shadcn: %w[toast alert badge] },
      'settings' => { icons: %w[Settings User Lock Key], shadcn: %w[tabs form switch] },
      'navigation' => { icons: %w[Menu X ChevronDown ChevronRight Home], shadcn: %w[navigation-menu sheet] },
      'media' => { icons: %w[Play Pause Volume Image Video Camera], shadcn: %w[button slider] },
      'calendar' => { icons: %w[Calendar Clock ChevronLeft ChevronRight], shadcn: %w[calendar date-picker] },
      'team' => { icons: %w[Users UserPlus UserMinus Shield], shadcn: %w[avatar card] },
      'chart' => { icons: %w[BarChart LineChart PieChart TrendingUp], shadcn: %w[card] },
      'table' => { icons: %w[Filter Sort ChevronUp ChevronDown], shadcn: %w[table] },
      'modal' => { icons: %w[X], shadcn: %w[dialog sheet] },
      'clickfunnels' => { icons: %w[Zap Crown Shield Check Star Award TrendingUp], shadcn: %w[button card badge] },
      'high convert' => { icons: %w[Zap Shield Check Star Crown Trophy], shadcn: %w[button card badge] }
    }
    
    def self.analyze(user_prompt, existing_files = [])
      new(user_prompt, existing_files).analyze
    end
    
    def initialize(user_prompt, existing_files = [])
      @prompt = user_prompt.downcase
      @existing_files = existing_files
      @required_icons = Set.new
      @required_shadcn = Set.new
      @required_sections = Set.new
    end
    
    def analyze
      # Detect app type from prompt
      app_type = detect_app_type
      
      # Add base requirements for detected app type
      if app_type && APP_PATTERNS[app_type]
        pattern = APP_PATTERNS[app_type]
        @required_icons.merge(pattern[:icons])
        @required_shadcn.merge(pattern[:shadcn])
        @required_sections.merge(pattern[:sections])
      end
      
      # Add keyword-triggered requirements
      KEYWORD_TRIGGERS.each do |keyword, requirements|
        if @prompt.include?(keyword.to_s)
          @required_icons.merge(requirements[:icons]) if requirements[:icons]
          @required_shadcn.merge(requirements[:shadcn]) if requirements[:shadcn]
        end
      end
      
      # Always include common UI icons
      @required_icons.merge(%w[Menu X ChevronDown Check Plus Minus])
      
      # Always include common shadcn components
      @required_shadcn.merge(%w[button card])
      
      {
        app_type: app_type,
        required_icons: @required_icons.to_a.sort,
        required_shadcn: @required_shadcn.to_a.sort,
        required_sections: @required_sections.to_a.sort,
        import_template: generate_import_template
      }
    end
    
    private
    
    def detect_app_type
      return 'landing' if @prompt.match?(/landing|homepage|website|portfolio|agency/)
      return 'saas' if @prompt.match?(/saas|software as a service|subscription/)
      return 'dashboard' if @prompt.match?(/dashboard|admin|analytics|metrics/)
      return 'todo' if @prompt.match?(/todo|task|checklist/)
      return 'ecommerce' if @prompt.match?(/ecommerce|shop|store|product|cart/)
      return 'blog' if @prompt.match?(/blog|article|post|content/)
      return 'chat' if @prompt.match?(/chat|message|conversation/)
      return 'form' if @prompt.match?(/form|survey|questionnaire/)
      return 'analytics' if @prompt.match?(/analytics|chart|graph|report/)
      return 'landing' # Default to landing page
    end
    
    def generate_import_template
      template = []
      
      # React imports
      template << "import React, { useState, useEffect } from 'react';"
      
      # Icon imports (chunked for readability)
      if @required_icons.any?
        icon_chunks = @required_icons.each_slice(5).to_a
        icon_chunks.each do |chunk|
          template << "import { #{chunk.join(', ')} } from 'lucide-react';"
        end
      end
      
      # Shadcn imports
      @required_shadcn.each do |component|
        case component
        when 'card'
          template << "import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';"
        when 'dialog'
          template << "import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';"
        when 'sheet'
          template << "import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/ui/sheet';"
        when 'tabs'
          template << "import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';"
        when 'form'
          template << "import { useForm } from 'react-hook-form';"
        else
          template << "import { #{component.split('-').map(&:capitalize).join} } from '@/components/ui/#{component}';"
        end
      end
      
      template.join("\n")
    end
  end
end