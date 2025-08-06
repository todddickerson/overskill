#!/usr/bin/env ruby
# Test script to create a multi-page app and test page switching

require_relative 'config/environment'

def create_multi_page_test_app
  puts "\n🚀 Creating Multi-Page Test App\n"
  puts "=" * 60
  
  # Find or create test team and user
  team = Team.first || Team.create!(name: "Test Team")
  user = User.first || User.create!(email: "test@example.com", password: "password123")
  
  # Ensure user is member of team
  unless team.memberships.exists?(user: user)
    team.memberships.create!(user: user, role_ids: ["admin"])
  end
  
  # Create test app
  app = team.apps.find_or_create_by!(name: "Multi-Page Test App") do |a|
    a.prompt = "A multi-page application with navigation"
    a.app_type = "business"
    a.framework = "vanilla"
    a.status = "generated"
  end
  
  puts "\n📱 Creating Multi-Page App: #{app.name}"
  puts "  ID: #{app.id}"
  
  # Clear existing files
  app.app_files.destroy_all
  
  # Create multiple HTML pages
  pages = [
    {
      path: "index.html",
      title: "Home",
      content: <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Home - Multi-Page App</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="styles.css">
        </head>
        <body class="font-['Inter'] antialiased bg-gray-50">
          <nav class="bg-white border-b border-gray-200">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <div class="flex justify-between h-16">
                <div class="flex items-center space-x-8">
                  <span class="text-lg font-semibold">MultiApp</span>
                  <div class="flex space-x-4">
                    <a href="index.html" class="px-3 py-2 rounded-md text-sm font-medium bg-gray-100">Home</a>
                    <a href="dashboard.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Dashboard</a>
                    <a href="about.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">About</a>
                    <a href="contact.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Contact</a>
                  </div>
                </div>
              </div>
            </div>
          </nav>
          
          <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <h1 class="text-3xl font-bold text-gray-900 mb-4">Welcome to Multi-Page App</h1>
            <p class="text-gray-600">This is the home page. Navigate using the menu above.</p>
            
            <div class="mt-8 grid grid-cols-1 md:grid-cols-3 gap-6">
              <div class="bg-white p-6 rounded-lg shadow">
                <h2 class="text-xl font-semibold mb-2">Feature 1</h2>
                <p class="text-gray-600">Description of feature one.</p>
              </div>
              <div class="bg-white p-6 rounded-lg shadow">
                <h2 class="text-xl font-semibold mb-2">Feature 2</h2>
                <p class="text-gray-600">Description of feature two.</p>
              </div>
              <div class="bg-white p-6 rounded-lg shadow">
                <h2 class="text-xl font-semibold mb-2">Feature 3</h2>
                <p class="text-gray-600">Description of feature three.</p>
              </div>
            </div>
          </main>
          
          <script src="app.js"></script>
        </body>
        </html>
      HTML
    },
    {
      path: "dashboard.html",
      title: "Dashboard",
      content: <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Dashboard - Multi-Page App</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="styles.css">
        </head>
        <body class="font-['Inter'] antialiased bg-gray-50">
          <nav class="bg-white border-b border-gray-200">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <div class="flex justify-between h-16">
                <div class="flex items-center space-x-8">
                  <span class="text-lg font-semibold">MultiApp</span>
                  <div class="flex space-x-4">
                    <a href="index.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Home</a>
                    <a href="dashboard.html" class="px-3 py-2 rounded-md text-sm font-medium bg-gray-100">Dashboard</a>
                    <a href="about.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">About</a>
                    <a href="contact.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Contact</a>
                  </div>
                </div>
              </div>
            </div>
          </nav>
          
          <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <h1 class="text-3xl font-bold text-gray-900 mb-4">Dashboard</h1>
            
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
              <div class="bg-white p-4 rounded-lg shadow">
                <div class="text-sm text-gray-500">Total Users</div>
                <div class="text-2xl font-bold">1,234</div>
              </div>
              <div class="bg-white p-4 rounded-lg shadow">
                <div class="text-sm text-gray-500">Revenue</div>
                <div class="text-2xl font-bold">$12,345</div>
              </div>
              <div class="bg-white p-4 rounded-lg shadow">
                <div class="text-sm text-gray-500">Growth</div>
                <div class="text-2xl font-bold text-green-600">+23%</div>
              </div>
              <div class="bg-white p-4 rounded-lg shadow">
                <div class="text-sm text-gray-500">Active Now</div>
                <div class="text-2xl font-bold">89</div>
              </div>
            </div>
            
            <div class="bg-white p-6 rounded-lg shadow">
              <h2 class="text-xl font-semibold mb-4">Recent Activity</h2>
              <div class="space-y-3">
                <div class="flex items-center justify-between py-2 border-b">
                  <span>New user registration</span>
                  <span class="text-sm text-gray-500">2 min ago</span>
                </div>
                <div class="flex items-center justify-between py-2 border-b">
                  <span>Payment received</span>
                  <span class="text-sm text-gray-500">15 min ago</span>
                </div>
                <div class="flex items-center justify-between py-2">
                  <span>Server update completed</span>
                  <span class="text-sm text-gray-500">1 hour ago</span>
                </div>
              </div>
            </div>
          </main>
          
          <script src="app.js"></script>
        </body>
        </html>
      HTML
    },
    {
      path: "about.html",
      title: "About",
      content: <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>About - Multi-Page App</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="styles.css">
        </head>
        <body class="font-['Inter'] antialiased bg-gray-50">
          <nav class="bg-white border-b border-gray-200">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <div class="flex justify-between h-16">
                <div class="flex items-center space-x-8">
                  <span class="text-lg font-semibold">MultiApp</span>
                  <div class="flex space-x-4">
                    <a href="index.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Home</a>
                    <a href="dashboard.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Dashboard</a>
                    <a href="about.html" class="px-3 py-2 rounded-md text-sm font-medium bg-gray-100">About</a>
                    <a href="contact.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Contact</a>
                  </div>
                </div>
              </div>
            </div>
          </nav>
          
          <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <h1 class="text-3xl font-bold text-gray-900 mb-4">About Us</h1>
            <div class="bg-white p-6 rounded-lg shadow">
              <p class="text-gray-600 mb-4">
                We are a company dedicated to building amazing multi-page applications.
                Our mission is to make web development accessible to everyone.
              </p>
              <p class="text-gray-600">
                Founded in 2024, we've helped thousands of businesses create their online presence.
              </p>
            </div>
          </main>
          
          <script src="app.js"></script>
        </body>
        </html>
      HTML
    },
    {
      path: "contact.html",
      title: "Contact",
      content: <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Contact - Multi-Page App</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
          <link rel="stylesheet" href="styles.css">
        </head>
        <body class="font-['Inter'] antialiased bg-gray-50">
          <nav class="bg-white border-b border-gray-200">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <div class="flex justify-between h-16">
                <div class="flex items-center space-x-8">
                  <span class="text-lg font-semibold">MultiApp</span>
                  <div class="flex space-x-4">
                    <a href="index.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Home</a>
                    <a href="dashboard.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">Dashboard</a>
                    <a href="about.html" class="px-3 py-2 rounded-md text-sm font-medium hover:bg-gray-100">About</a>
                    <a href="contact.html" class="px-3 py-2 rounded-md text-sm font-medium bg-gray-100">Contact</a>
                  </div>
                </div>
              </div>
            </div>
          </nav>
          
          <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
            <h1 class="text-3xl font-bold text-gray-900 mb-4">Contact Us</h1>
            <div class="bg-white p-6 rounded-lg shadow max-w-2xl">
              <form class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">Name</label>
                  <input type="text" class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500">
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">Email</label>
                  <input type="email" class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500">
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-700 mb-2">Message</label>
                  <textarea rows="4" class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"></textarea>
                </div>
                <button type="submit" class="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700">
                  Send Message
                </button>
              </form>
            </div>
          </main>
          
          <script src="app.js"></script>
        </body>
        </html>
      HTML
    }
  ]
  
  # Create all HTML pages
  pages.each do |page_data|
    file = app.app_files.create!(
      path: page_data[:path],
      content: page_data[:content],
      file_type: "html"
    )
    puts "  ✅ Created: #{page_data[:path]} - #{page_data[:title]} page"
  end
  
  # Create shared JavaScript
  app.app_files.create!(
    path: "app.js",
    content: <<~JS
      // Shared JavaScript for all pages
      const app = {
        currentPage: window.location.pathname.split('/').pop() || 'index.html',
        
        init() {
          console.log('Multi-Page App initialized on:', this.currentPage);
          this.highlightActiveNav();
        },
        
        highlightActiveNav() {
          // Highlight the current page in navigation
          document.querySelectorAll('nav a').forEach(link => {
            const href = link.getAttribute('href');
            if (href === this.currentPage) {
              console.log('Active page:', href);
            }
          });
        }
      };
      
      // Initialize when DOM is ready
      document.addEventListener('DOMContentLoaded', () => app.init());
    JS
    file_type: "js"
  )
  puts "  ✅ Created: app.js - Shared JavaScript"
  
  # Create shared styles
  app.app_files.create!(
    path: "styles.css",
    content: <<~CSS
      /* Shared styles for all pages */
      :root {
        --primary: #3b82f6;
        --secondary: #64748b;
      }
      
      /* Custom styles can be added here */
    CSS
    file_type: "css"
  )
  puts "  ✅ Created: styles.css - Shared styles"
  
  puts "\n" + "=" * 60
  puts "✅ Multi-Page Test App Created Successfully!"
  puts "\n📁 Created #{app.app_files.count} files:"
  app.app_files.each do |file|
    puts "  • #{file.path} (#{file.file_type})"
  end
  
  puts "\n🌐 View the app at:"
  puts "  http://localhost:3000/account/apps/#{app.id}/editor"
  puts "\n📝 Test the page switcher:"
  puts "  1. Open the editor"
  puts "  2. Click on Preview tab"
  puts "  3. Use the page dropdown to switch between pages"
  puts "  4. Each page should load with its unique content"
  
  app
end

# Run the test
if __FILE__ == $0
  create_multi_page_test_app
end