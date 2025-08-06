class Public::GeneratorController < Public::ApplicationController
  # Simple, streamlined app generation starting point
  # No complex forms, just a description and starter prompts
  
  STARTER_PROMPTS = [
    {
      title: "Team Collaboration",
      description: "Real-time chat, file sharing, and project management",
      prompt: "Create a team collaboration platform with chat rooms, file sharing, task management, and video calls",
      icon: "👥"
    },
    {
      title: "Online Marketplace", 
      description: "Buy and sell with integrated payments",
      prompt: "Build a marketplace where users can list products, make purchases with Stripe, and leave reviews",
      icon: "🛍️"
    },
    {
      title: "Learning Platform",
      description: "Courses, quizzes, and progress tracking", 
      prompt: "Design an online learning platform with video courses, interactive quizzes, and student progress tracking",
      icon: "📚"
    },
    {
      title: "Social Community",
      description: "Connect, share, and engage with others",
      prompt: "Create a social community app with user profiles, posts, comments, likes, and real-time notifications",
      icon: "🌐"
    },
    {
      title: "Business Dashboard",
      description: "Analytics, reports, and data visualization",
      prompt: "Build a business analytics dashboard with charts, KPI tracking, and automated reporting",
      icon: "📊"
    },
    {
      title: "Custom App",
      description: "Describe your unique idea",
      prompt: nil,  # User will provide their own
      icon: "✨"
    }
  ].freeze
  
  def index
    # Simple landing page with prompt selection
    @starter_prompts = STARTER_PROMPTS
    
    # Check if we have a prompt parameter (from post-auth redirect)
    if params[:prompt].present? && user_signed_in?
      # Auto-submit the form with the pending prompt
      create
    end
  end
  
  def create
    # Handle app generation request
    prompt = params[:prompt] || params[:custom_prompt]
    
    if prompt.blank?
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Please provide an app description" }
        format.json { render json: { error: "Please provide an app description" }, status: :unprocessable_entity }
      end
      return
    end
    
    # Check if user is signed in
    unless user_signed_in?
      # Store the prompt in session to use after authentication
      session[:pending_app_prompt] = prompt
      
      respond_to do |format|
        format.html { redirect_to new_user_session_path, alert: "Please sign in to create an app" }
        format.json { render json: { requires_auth: true, prompt: prompt }, status: :unauthorized }
      end
      return
    end
    
    # Create app with our single optimized stack
    app = current_team.apps.create!(
      creator: current_membership,
      name: generate_app_name(prompt),
      slug: generate_unique_slug,
      prompt: enhance_prompt(prompt),
      app_type: "saas",  # Single type
      framework: "react", # Single framework
      status: "draft",
      base_price: 0,
      visibility: "private"
    )
    
    # Create initial message
    message = app.app_chat_messages.create!(
      role: "user",
      content: enhance_prompt(prompt),
      user: current_user
    )
    
    # Queue generation
    if ENV['USE_UNIFIED_AI'] == 'true'
      UnifiedAiProcessingJob.perform_later(message)
    else
      # Create generation record
      generation = app.app_generations.create!(
        team: current_team,
        started_at: Time.current,
        status: "pending"
      )
      AppGenerationJob.perform_later(generation)
    end
    
    # Respond appropriately
    respond_to do |format|
      format.html { redirect_to account_app_editor_path(app), notice: "Creating your app..." }
      format.json { render json: { success: true, redirect_url: account_app_editor_path(app) } }
    end
  end
  
  private
  
  def create_guest_user
    # Create a guest user for trying the platform
    email = "guest_#{SecureRandom.hex(8)}@overskill.app"
    password = SecureRandom.hex(16)
    
    user = User.create!(
      email: email,
      password: password,
      name: "Guest User",
      time_zone: "UTC"
    )
    
    # Create a trial team
    team = Team.create!(
      name: "Trial Team #{user.id}",
      time_zone: "UTC"
    )
    
    # Create membership
    team.memberships.create!(
      user: user,
      user_name: user.name,
      user_email: user.email,
      role_ids: ["default"]
    )
    
    user
  end
  
  def generate_app_name(prompt)
    # Extract a name from the prompt or generate one
    words = prompt.split.select { |w| w.length > 3 }.first(3)
    words.any? ? words.join(" ").titleize : "My App #{Time.current.to_i}"
  end
  
  def generate_unique_slug
    "app-#{SecureRandom.hex(6)}"
  end
  
  def enhance_prompt(prompt)
    # Add our tech stack requirements to every prompt
    <<~ENHANCED
      #{prompt}
      
      Build this as a modern SaaS application with:
      - React with TypeScript for the frontend
      - Cloudflare Workers for serverless backend
      - Supabase for database with row-level security
      - Supabase Auth with social logins (Google, GitHub)
      - Stripe Connect for payments
      - Real-time updates where applicable
      - Mobile-responsive design
      - Dark mode support
      - Accessibility features
      
      Make it production-ready with proper error handling, loading states, and security.
    ENHANCED
  end
end