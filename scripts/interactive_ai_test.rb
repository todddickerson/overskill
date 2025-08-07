#!/usr/bin/env ruby
# Interactive AI Generation Testing Script
# Run with: bin/rails runner scripts/interactive_ai_test.rb

require 'benchmark'
require 'json'

class InteractiveAITester
  def initialize
    @test_session = {
      started_at: Time.current,
      app: nil,
      generation_steps: [],
      update_steps: [],
      total_time: 0
    }
  end

  def run
    puts "=" * 80
    puts "🤖 INTERACTIVE AI GENERATION TESTING"
    puts "=" * 80
    
    # Step 1: Setup
    setup_test_environment
    
    # Step 2: Generate initial app
    generate_initial_app
    
    # Step 3: Present results and get user input
    present_generation_results
    
    # Step 4: Simulate chat updates
    simulate_chat_updates
    
    # Final summary
    present_final_summary
  end

  private

  def setup_test_environment
    puts "\n[SETUP] Preparing test environment..."
    puts "-" * 40
    
    # Get or create test team and user
    @team = Team.find_by(name: "AI Test Team") || Team.create!(name: "AI Test Team")
    @user = User.find_by(email: "ai-test@overskill.app") || User.create!(
      email: "ai-test@overskill.app",
      password: "test123456",
      first_name: "AI",
      last_name: "Tester"
    )
    
    # Ensure user is member of team
    @membership = @team.memberships.find_by(user: @user) || @team.memberships.create!(
      user: @user,
      role_ids: ["admin"]
    )
    
    puts "✅ Test team: #{@team.name} (ID: #{@team.id})"
    puts "✅ Test user: #{@user.email} (ID: #{@user.id})"
    puts "✅ Membership: #{@membership.role_ids.join(', ')}"
  end

  def generate_initial_app
    puts "\n[GENERATION] Creating and generating new app..."
    puts "-" * 40
    
    app_name = "Interactive Test App #{Time.current.to_i}"
    prompt = build_comprehensive_prompt
    
    # Create app record
    @app = @team.apps.create!(
      name: app_name,
      prompt: prompt,
      status: 'generating',
      app_type: 'saas',
      framework: 'react',
      creator: @membership
    )
    
    puts "✅ Created app: #{@app.name} (ID: #{@app.id})"
    @test_session[:app] = @app
    
    # Generate with real AI
    generation_time = Benchmark.measure do
      generate_with_ai(@app, prompt, "Initial generation")
    end
    
    @test_session[:total_time] += generation_time.real
    puts "⏱️  Generation completed in #{generation_time.real.round(2)}s"
  end

  def generate_with_ai(app, content, step_name)
    puts "\n🤖 Running AI generation: #{step_name}"
    
    # Create chat message (user messages don't have status)
    message = app.app_chat_messages.create!(
      user: @user,
      role: 'user',
      content: content
    )
    
    step_info = {
      step_name: step_name,
      message_id: message.id,
      started_at: Time.current,
      files_before: app.app_files.count
    }
    
    begin
      # Use the real AI orchestrator
      orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
      result = orchestrator.execute!
      
      step_info[:completed_at] = Time.current
      step_info[:success] = result[:success]
      step_info[:files_after] = app.app_files.count
      step_info[:files_changed] = step_info[:files_after] - step_info[:files_before]
      step_info[:response] = result[:response] if result[:response]
      step_info[:error] = result[:error] if result[:error]
      
      if result[:success]
        puts "✅ #{step_name} successful"
        puts "   Files changed: #{step_info[:files_changed]}"
        # Update with ai_response but no status (user messages don't have status)
        message.update!(ai_response: result[:response])
        app.update!(status: 'generated') if app.status == 'generating'
      else
        puts "❌ #{step_name} failed: #{result[:error]}"
        # Don't set status on user messages
        app.update!(status: 'failed')
      end
      
    rescue => e
      step_info[:completed_at] = Time.current
      step_info[:success] = false
      step_info[:error] = e.message
      step_info[:backtrace] = e.backtrace.first(3)
      
      puts "❌ #{step_name} error: #{e.message}"
      # Don't set status on user messages
      app.update!(status: 'failed')
    end
    
    @test_session[:generation_steps] << step_info
    step_info
  end

  def present_generation_results
    puts "\n" + "=" * 80
    puts "📊 GENERATION RESULTS REVIEW"
    puts "=" * 80
    
    # App details
    puts "\n📱 App Details:"
    puts "  ID: #{@app.id}"
    puts "  Name: #{@app.name}"
    puts "  Status: #{@app.status}"
    puts "  Files: #{@app.app_files.count}"
    
    # File breakdown
    puts "\n📁 File Breakdown:"
    file_types = @app.app_files.group_by { |f| File.extname(f.path) }
    file_types.each do |ext, files|
      ext_name = ext.empty? ? "no extension" : ext
      puts "  #{ext_name}: #{files.count} files"
    end
    
    # Key files check
    puts "\n🔍 Key Files Analysis:"
    key_files = [
      "package.json",
      "src/main.tsx",
      "src/App.tsx", 
      "src/lib/supabase.ts",
      "src/pages/auth/Login.tsx",
      "src/pages/auth/Signup.tsx",
      "src/components/auth/SocialButtons.tsx",
      "src/hooks/useAuth.ts",
      "index.html"
    ]
    
    key_files.each do |path|
      file = @app.app_files.find_by(path: path)
      status = file ? "✅" : "❌"
      size = file ? "(#{file.content.length} chars)" : ""
      puts "  #{status} #{path} #{size}"
    end
    
    # Deploy app
    puts "\n🚀 Deploying app for review..."
    deploy_app
    
    # Present review interface
    present_review_interface
  end

  def deploy_app
    if @app.status == 'generated'
      begin
        deploy_service = Deployment::CloudflarePreviewService.new(@app)
        result = deploy_service.update_preview!
        
        if result[:success]
          puts "✅ Deployment successful"
          puts "   URL: #{result[:preview_url]}"
          @app.update!(
            status: 'published',
            preview_url: result[:preview_url],
            deployed_at: Time.current
          )
        else
          puts "❌ Deployment failed: #{result[:error]}"
        end
      rescue => e
        puts "❌ Deploy error: #{e.message}"
      end
    end
  end

  def present_review_interface
    puts "\n" + "=" * 80
    puts "🎯 INTERACTIVE REVIEW INTERFACE"
    puts "=" * 80
    
    if @app.preview_url
      puts "\n🌐 Live App: #{@app.preview_url}"
      puts "\n📋 Review Checklist:"
      puts "  □ Open the app URL above"
      puts "  □ Test the login/signup functionality"
      puts "  □ Check OAuth providers (Google/GitHub)"
      puts "  □ Verify the main app features work"
      puts "  □ Test mobile responsiveness"
    else
      puts "\n⚠️  App not deployed - reviewing code only"
    end
    
    puts "\n" + "-" * 40
    puts "What would you like to do next?"
    puts "1. Add a new feature"
    puts "2. Fix a bug"
    puts "3. Improve the UI"
    puts "4. Add more OAuth providers"
    puts "5. Skip to final summary"
    puts "-" * 40
    
    print "Enter your choice (1-5): "
    choice = gets.chomp.to_i
    
    handle_user_choice(choice)
  end

  def handle_user_choice(choice)
    case choice
    when 1
      simulate_feature_addition
    when 2
      simulate_bug_fix
    when 3
      simulate_ui_improvement
    when 4
      simulate_oauth_enhancement
    when 5
      puts "⏭️  Skipping to final summary..."
    else
      puts "Invalid choice, skipping to summary..."
    end
  end

  def simulate_feature_addition
    puts "\n🆕 Simulating Feature Addition..."
    
    feature_prompt = "Add a task priority system with the following features:

1. **Priority Levels**: Add High, Medium, Low priority options to tasks
2. **Visual Indicators**: Use color coding (red for high, yellow for medium, green for low)
3. **Priority Filter**: Allow filtering tasks by priority level
4. **Priority Sorting**: Sort tasks by priority in the task list
5. **Priority Statistics**: Show count of tasks by priority in a dashboard widget

Make sure to:
- Update the task creation/edit forms
- Modify the database schema if needed
- Update the task display components
- Add priority-based styling with Tailwind CSS
- Maintain user data isolation"

    update_time = Benchmark.measure do
      generate_with_ai(@app, feature_prompt, "Add priority system")
    end
    
    @test_session[:total_time] += update_time.real
    puts "⏱️  Feature addition completed in #{update_time.real.round(2)}s"
    
    # Redeploy
    puts "\n🔄 Redeploying with new feature..."
    deploy_app
    
    present_update_review("Priority System Feature")
  end

  def simulate_bug_fix
    puts "\n🐛 Simulating Bug Fix..."
    
    bug_fix_prompt = "Fix common authentication issues:

1. **Session Persistence**: Ensure user stays logged in across browser refreshes
2. **Logout Functionality**: Add proper logout button that clears all session data
3. **Protected Routes**: Ensure unauthenticated users are redirected to login
4. **Loading States**: Add loading indicators during authentication processes
5. **Error Boundaries**: Add proper error handling for auth failures

Focus on:
- Improving the AuthContext implementation
- Adding session validation checks
- Implementing proper cleanup on logout
- Better error messaging for users"

    update_time = Benchmark.measure do
      generate_with_ai(@app, bug_fix_prompt, "Fix authentication issues")
    end
    
    @test_session[:total_time] += update_time.real
    puts "⏱️  Bug fix completed in #{update_time.real.round(2)}s"
    
    # Redeploy
    puts "\n🔄 Redeploying with bug fixes..."
    deploy_app
    
    present_update_review("Authentication Bug Fixes")
  end

  def simulate_ui_improvement
    puts "\n🎨 Simulating UI Improvement..."
    
    ui_prompt = "Enhance the user interface with modern improvements:

1. **Dark/Light Theme Toggle**: Add theme switcher with persistent preference
2. **Improved Animations**: Add smooth transitions and micro-interactions
3. **Better Mobile UX**: Optimize for mobile with better touch targets and spacing
4. **Loading Skeletons**: Replace loading spinners with skeleton screens
5. **Empty States**: Add beautiful empty state illustrations and messaging

Design improvements:
- Use modern card designs with subtle shadows
- Improve typography with better font hierarchy
- Add hover states and focus indicators
- Implement responsive grid layouts
- Add success/error toast notifications"

    update_time = Benchmark.measure do
      generate_with_ai(@app, ui_prompt, "UI/UX improvements")
    end
    
    @test_session[:total_time] += update_time.real
    puts "⏱️  UI improvements completed in #{update_time.real.round(2)}s"
    
    # Redeploy
    puts "\n🔄 Redeploying with UI improvements..."
    deploy_app
    
    present_update_review("UI/UX Enhancements")
  end

  def simulate_oauth_enhancement
    puts "\n🔐 Simulating OAuth Enhancement..."
    
    oauth_prompt = "Enhance OAuth authentication with additional providers and features:

1. **Apple Sign-In**: Add Apple OAuth provider
2. **Microsoft OAuth**: Add Microsoft/Office 365 login
3. **Profile Management**: Add user profile page with avatar upload
4. **Account Linking**: Allow users to link multiple OAuth providers
5. **Enhanced Security**: Add two-factor authentication option

Implementation details:
- Update Supabase configuration for new providers
- Add provider-specific buttons with proper branding
- Implement profile picture fetching from OAuth providers
- Add account settings page
- Maintain secure session management"

    update_time = Benchmark.measure do
      generate_with_ai(@app, oauth_prompt, "OAuth enhancements")
    end
    
    @test_session[:total_time] += update_time.real
    puts "⏱️  OAuth enhancements completed in #{update_time.real.round(2)}s"
    
    # Redeploy
    puts "\n🔄 Redeploying with OAuth enhancements..."
    deploy_app
    
    present_update_review("OAuth Provider Enhancements")
  end

  def present_update_review(update_name)
    puts "\n" + "=" * 60
    puts "📊 UPDATE REVIEW: #{update_name}"
    puts "=" * 60
    
    # Show file changes
    puts "\n📁 File Changes:"
    puts "  Total files: #{@app.app_files.count}"
    
    # Show recent messages
    recent_messages = @app.app_chat_messages.order(created_at: :desc).limit(2)
    puts "\n💬 Recent AI Messages:"
    recent_messages.each do |msg|
      puts "  #{msg.created_at.strftime('%H:%M')} - #{msg.role}: #{msg.status}"
      if msg.ai_response
        preview = msg.ai_response.length > 100 ? msg.ai_response[0..100] + "..." : msg.ai_response
        puts "    Response: #{preview}"
      end
    end
    
    if @app.preview_url
      puts "\n🌐 Updated App: #{@app.preview_url}"
      puts "\nPlease review the changes and press Enter to continue..."
      gets
    end
  end

  def simulate_chat_updates
    puts "\n[CHAT SIMULATION] Running additional updates..."
    puts "-" * 40
    
    # We already handled this in the user choice methods
    puts "✅ Chat updates completed through interactive choices"
  end

  def present_final_summary
    puts "\n" + "=" * 80
    puts "🎉 FINAL TEST SUMMARY"
    puts "=" * 80
    
    # Timing summary
    puts "\n⏱️  Performance Summary:"
    puts "  Total test time: #{@test_session[:total_time].round(2)}s"
    puts "  Generation steps: #{@test_session[:generation_steps].count}"
    
    # Step breakdown
    puts "\n📋 Step Breakdown:"
    @test_session[:generation_steps].each_with_index do |step, index|
      duration = step[:completed_at] ? (step[:completed_at] - step[:started_at]).round(2) : "N/A"
      status = step[:success] ? "✅" : "❌"
      puts "  #{index + 1}. #{status} #{step[:step_name]} (#{duration}s)"
      if step[:files_changed] && step[:files_changed] > 0
        puts "     Files changed: #{step[:files_changed]}"
      end
      if step[:error]
        puts "     Error: #{step[:error]}"
      end
    end
    
    # Final app state
    puts "\n📱 Final App State:"
    puts "  ID: #{@app.id}"
    puts "  Name: #{@app.name}"
    puts "  Status: #{@app.status}"
    puts "  Files: #{@app.app_files.count}"
    puts "  Messages: #{@app.app_chat_messages.count}"
    puts "  URL: #{@app.preview_url || 'Not deployed'}"
    
    # Success metrics
    successful_steps = @test_session[:generation_steps].count { |s| s[:success] }
    success_rate = (successful_steps.to_f / @test_session[:generation_steps].count * 100).round(1)
    
    puts "\n📊 Success Metrics:"
    puts "  Successful steps: #{successful_steps}/#{@test_session[:generation_steps].count}"
    puts "  Success rate: #{success_rate}%"
    
    # Performance rating
    puts "\n🏆 Performance Rating:"
    avg_step_time = @test_session[:total_time] / @test_session[:generation_steps].count
    if avg_step_time < 30
      puts "  🚀 EXCELLENT! Average #{avg_step_time.round(1)}s per step"
    elsif avg_step_time < 60
      puts "  ✅ GOOD! Average #{avg_step_time.round(1)}s per step"
    else
      puts "  ⚠️  SLOW! Average #{avg_step_time.round(1)}s per step"
    end
    
    puts "\n" + "=" * 80
    puts "Test completed at: #{Time.current}"
    puts "=" * 80
  end

  def build_comprehensive_prompt
    <<~PROMPT
      Create a comprehensive task management application called "TaskFlow Pro" with the following specifications:

      ## Core Features
      - **User Authentication**: Login, signup, password reset, OAuth (Google + GitHub)
      - **Task Management**: Full CRUD operations with title, description, due date, status
      - **User Data Isolation**: Each user sees only their own tasks
      - **Real-time Updates**: Instant sync with Supabase

      ## Advanced Functionality
      - Task filtering by status and due date
      - Task sorting by multiple criteria
      - Task search functionality
      - Mark tasks complete with animations
      - Bulk operations support

      ## Technical Requirements
      - React with TypeScript for type safety
      - Supabase for database and authentication
      - Modern React patterns (hooks, context)
      - Tailwind CSS for styling
      - Responsive design for all devices
      - Loading states and error handling
      - Performance optimizations

      ## Authentication Features
      - Email/password authentication
      - Google OAuth integration
      - GitHub OAuth integration  
      - Protected routes
      - Session management
      - Password reset flow
      - User profile management

      ## UI/UX Requirements
      - Professional, modern design
      - Smooth animations and transitions
      - Mobile-first responsive design
      - Dark/light theme support
      - Toast notifications
      - Loading skeletons
      - Empty state designs

      Please ensure the app uses proper TypeScript types, follows React best practices, and implements secure authentication flows with our enhanced PKCE validation system.
    PROMPT
  end
end

# Run the interactive test
if __FILE__ == $0
  tester = InteractiveAITester.new
  tester.run
end