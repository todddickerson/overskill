#!/usr/bin/env ruby
# Minimal test for chat development components without full Rails environment

require 'minitest/autorun'
require 'active_support/all'
require 'json'
require 'ostruct'
require 'logger'
require 'pathname'

# Minimal setup for testing our classes
class MockApp
  attr_accessor :id, :app_files, :name, :slug, :team, :creator, :prompt
  
  def initialize
    @id = 123
    @app_files = MockAppFiles.new
    @name = "Test App"
    @slug = "test-app"
    @prompt = "Test prompt"
  end
end

class MockAppFiles
  def initialize
    @files = []
  end
  
  def create!(attributes)
    @files << MockAppFile.new(attributes)
  end
  
  def find_by(path:)
    @files.find { |f| f.path == path }
  end
  
  def where(conditions = {})
    @files
  end
  
  def count
    @files.count
  end
  
  def exists?(path:)
    @files.any? { |f| f.path == path }
  end
end

class MockAppFile
  attr_accessor :path, :content, :team
  
  def initialize(attributes = {})
    @path = attributes[:path]
    @content = attributes[:content] || ""
    @team = attributes[:team]
  end
  
  def size
    @content.size
  end
end

class MockAppChatMessage
  attr_accessor :content, :user, :role, :app
  
  def initialize(attributes = {})
    @content = attributes[:content]
    @user = attributes[:user]
    @role = attributes[:role] || 'user'
    @app = attributes[:app]
  end
end

# Mock Rails module for our service
module Rails
  def self.logger
    @logger ||= Logger.new(STDOUT).tap { |l| l.level = Logger::ERROR }
  end
  
  def self.root
    Pathname.new(File.expand_path('.', __dir__))
  end
end

# Load our service files
require_relative 'app/services/ai/file_context_analyzer'

class ChatDevelopmentMinimalTest < Minitest::Test
  def setup
    @app = MockApp.new
    @user = OpenStruct.new(id: 1, email: 'test@example.com')
    @message = MockAppChatMessage.new(
      content: 'Add user authentication',
      user: @user,
      app: @app
    )
  end
  
  def test_file_context_analyzer_initialization
    analyzer = Ai::FileContextAnalyzer.new(@app)
    assert_not_nil analyzer
  end
  
  def test_file_context_analyzer_empty_app
    analyzer = Ai::FileContextAnalyzer.new(@app)
    context = analyzer.analyze
    
    assert_not_nil context
    assert_equal 0, context[:file_structure][:total_files]
    assert_empty context[:existing_components]
    assert_empty context[:dependencies]
  end
  
  def test_file_context_analyzer_with_files
    # Add some mock files
    @app.app_files.create!(
      path: 'src/components/TestComponent.tsx',
      content: <<~TSX
        import React, { useState } from 'react';
        
        interface TestProps {
          title: string;
          optional?: boolean;
        }
        
        export default function TestComponent({ title, optional }: TestProps) {
          const [count, setCount] = useState(0);
          
          return (
            <div className="bg-blue-500 text-white p-4">
              <h1>{title}</h1>
              <button onClick={() => setCount(count + 1)}>
                Count: {count}
              </button>
            </div>
          );
        }
      TSX
    )
    
    @app.app_files.create!(
      path: 'package.json',
      content: JSON.generate({
        "name" => "test-app",
        "dependencies" => {
          "react" => "^18.0.0",
          "tailwindcss" => "^3.0.0"
        }
      })
    )
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    context = analyzer.analyze
    
    assert_not_nil context
    assert_operator context[:file_structure][:total_files], :>, 0
    assert context[:existing_components]['TestComponent'].present?
    assert context[:dependencies][:dependencies]['react'].present?
  end
  
  def test_component_analysis
    # Add a component file
    @app.app_files.create!(
      path: 'src/components/AuthForm.tsx',
      content: <<~TSX
        import React, { useState, useEffect } from 'react';
        import { Button } from '@/components/ui/button';
        
        interface AuthFormProps {
          mode: 'login' | 'signup';
          onSubmit: (data: FormData) => void;
        }
        
        export default function AuthForm({ mode, onSubmit }: AuthFormProps) {
          const [email, setEmail] = useState('');
          const [password, setPassword] = useState('');
          const [loading, setLoading] = useState(false);
          
          useEffect(() => {
            console.log('AuthForm mounted');
          }, []);
          
          const handleSubmit = (e: React.FormEvent) => {
            e.preventDefault();
            setLoading(true);
            onSubmit({ email, password });
          };
          
          return (
            <form onSubmit={handleSubmit} className="space-y-4">
              <input 
                type="email" 
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="w-full p-2 border rounded"
                placeholder="Email"
              />
              <input 
                type="password" 
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full p-2 border rounded"
                placeholder="Password"
              />
              <Button type="submit" disabled={loading}>
                {loading ? 'Loading...' : mode === 'login' ? 'Login' : 'Sign Up'}
              </Button>
            </form>
          );
        }
      TSX
    )
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    context = analyzer.analyze
    
    # Check component detection
    auth_form = context[:existing_components]['AuthForm']
    assert_not_nil auth_form
    assert_equal 'AuthForm', auth_form[:name]
    assert_equal :stateful_component, auth_form[:type]
    
    # Check props detection
    props = auth_form[:props]
    mode_prop = props.find { |p| p[:name] == 'mode' }
    assert_not_nil mode_prop
    assert_equal "'login' | 'signup'", mode_prop[:type]
    
    # Check UI framework detection
    assert_includes auth_form[:ui_framework], 'tailwind'
    
    # Check state management
    assert_includes auth_form[:state_management], 'useState'
  end
end

puts "🧪 Running Minimal Chat Development Tests"
puts "=========================================="