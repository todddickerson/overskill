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
    @user_signed_in = user_signed_in?
    
    # Check if we have a pending generation from cookies
    if cookies.encrypted[:pending_generation].present? && user_signed_in?
      generation_data = JSON.parse(cookies.encrypted[:pending_generation])
      prompt = generation_data["prompt"]
      cookies.delete(:pending_generation)
      
      # Process the pending generation
      if prompt.present?
        # Call create action directly with the stored prompt
        params[:prompt] = prompt
        create
      end
    end
  end
  
  def create
    # Handle app generation request
    prompt = params[:prompt] || params[:custom_prompt]
    ai_model = params[:ai_model] || 'claude-sonnet-4-20250514'  # Default to Claude Sonnet 4
    
    if prompt.blank?
      redirect_to root_path, alert: "Please provide an app description"
      return
    end
    
    # Check if user is signed in
    unless user_signed_in?
      # Store the generation request in an encrypted cookie
      cookies.encrypted[:pending_generation] = {
        value: { prompt: prompt, ai_model: ai_model }.to_json,
        expires: 20.minutes.from_now
      }
      
      # Respond based on request format
      respond_to do |format|
        format.html { redirect_to new_user_session_path }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "auth_modal",
            partial: "shared/auth_modal",
            locals: { show: true, prompt: prompt }
          )
        end
      end
      return
    end
    
    # Create app with our single optimized stack
    # The App model will automatically initiate AI generation via after_create callback
    app = current_team.apps.create!(
      creator: current_membership,
      name: generate_app_name(prompt),
      slug: generate_unique_slug,
      prompt: prompt,
      app_type: "saas",  # Single type
      framework: "react", # Single framework
      status: "draft",
      base_price: 0,
      visibility: "private",
      ai_model: ai_model  # Use selected AI model
    )
    
    # App model's after_create callback will handle:
    # 1. Creating initial chat message
    # 2. Determining which AI system to use (V3, Unified, or Legacy)
    # 3. Queuing the appropriate job
    # 4. Setting status to "generating"
    
    # Redirect to editor immediately so user can watch generation progress
    respond_to do |format|
      format.html { redirect_to account_app_editor_path(app), notice: "Creating your app..." }
      format.turbo_stream do
        # Redirect via JavaScript for turbo_stream requests
        render turbo_stream: turbo_stream.append(
          "body", 
          html: "<script>window.location.href = '#{account_app_editor_path(app)}';</script>"
        )
      end
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
end