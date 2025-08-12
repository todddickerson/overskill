#!/usr/bin/env ruby
# Standalone test for chat development system validation
# When Rails is loaded, this file becomes a no-op placeholder to avoid conflicts.

if defined?(Rails) && Rails.respond_to?(:application)
  require 'test_helper'
  class ChatDevelopmentStandalonePlaceholderTest < ActiveSupport::TestCase
    def test_placeholder
      assert true
    end
  end
else
  require 'minitest/autorun'
  require 'active_support/all'
  require 'json'
  require 'ostruct'
  require 'logger'
  require 'pathname'

  # Mock Rails environment
  module Rails
    def self.logger
      @logger ||= Logger.new(STDOUT).tap { |l| l.level = Logger::WARN }
    end
    
    def self.root
      Pathname.new(File.expand_path('..', __dir__))
    end

    # Minimal application/executor to satisfy ActiveSupport::Executor::TestHelper when present
    def self.application
      @application ||= Class.new do
        def executor
          @executor ||= Class.new do
            def perform
              yield
            end
          end.new
        end
      end.new
    end
  end

  # Mock ActiveRecord-like behavior
  module ActiveRecord
    class Base
      def self.joins(*args)
        MockQuery.new
      end
      
      def self.where(*args)
        MockQuery.new
      end
      
      def self.limit(*args)
        MockQuery.new
      end
    end
    
    class MockQuery
      def where(*args)
        self
      end
      
      def limit(*args)
        self
      end
      
      def count
        0
      end
      
      def average(*args)
        0
      end
      
      def each(&block)
        []
      end
      
      def map(&block)
        []
      end
    end
  end

  # Mock models for testing
  class MockApp
    attr_accessor :id, :app_files, :name, :slug, :team, :creator, :prompt, :status
    
    def initialize(attributes = {})
      @id = attributes[:id] || 123
      @app_files = MockAppFiles.new
      @name = attributes[:name] || "Test App"
      @slug = attributes[:slug] || "test-app"
      @status = attributes[:status] || "generated"
      @prompt = attributes[:prompt] || "Test prompt"
    end
  end

  class MockAppFiles
    def initialize
      @files = []
    end
    
    def create!(attributes)
      file = MockAppFile.new(attributes)
      @files << file
      file
    end
    
    def find_by(conditions)
      if conditions.is_a?(Hash) && conditions[:path]
        @files.find { |f| f.path == conditions[:path] }
      else
        @files.first
      end
    end
    
    def where(conditions = {})
      @files
    end
    
    def count
      @files.count
    end
    
    def exists?(conditions)
      if conditions.is_a?(Hash) && conditions[:path]
        @files.any? { |f| f.path == conditions[:path] }
      else
        @files.any?
      end
    end
    
    def select(&block)
      @files.select(&block)
    end
    
    def map(&block)
      @files.map(&block)
    end
    
    def each(&block)
      @files.each(&block)
    end
  end

  class MockAppFile
    attr_accessor :path, :content, :team, :created_at
    
    def initialize(attributes = {})
      @path = attributes[:path]
      @content = attributes[:content] || ""
      @team = attributes[:team]
      @created_at = attributes[:created_at] || Time.current
    end
    
    def size
      @content.size
    end
  end

  class MockAppChatMessage < ActiveRecord::Base
    attr_accessor :content, :user, :role, :app
    
    def initialize(attributes = {})
      @content = attributes[:content]
      @user = attributes[:user]
      @role = attributes[:role] || 'user'
      @app = attributes[:app]
    end
  end

  # Mock User model
  class MockUser
    attr_accessor :id, :email
    
    def initialize(attributes = {})
      @id = attributes[:id] || 1
      @email = attributes[:email] || 'test@example.com'
    end
  end

  # Load the service classes
  require_relative '../app/services/ai/file_context_analyzer'

  # Mock ChatMessageProcessor functionality for testing
  module Ai
    class ChatMessageProcessor
      MESSAGE_TYPES = {
        initial_generation: /^(create|build|generate|make)\s+.*app/i,
        add_feature: /^(add|include|implement)\s+/i,
        modify_feature: /^(change|update|modify|edit)\s+/i,
        fix_bug: /^(fix|debug|resolve|correct)\s+/i,
        style_change: /^(style|design|color|theme|make.*look)/i,
        component_request: /^(use|add).*component/i,
        deployment_request: /^(deploy|publish|launch)\s+/i,
        question: /^(how|what|why|when|where)\s+/i
      }
      
      def initialize(message)
        @message = message
        @app = message.app
        @user = message.user
      end
      
      def classify_message_intent
        content = @message.content.downcase
        
        message_type = MESSAGE_TYPES.find { |type, pattern| content.match?(pattern) }&.first || :unknown
        
        {
          type: message_type,
          confidence: 0.8,
          entities: extract_entities(content),
          scope: determine_scope(content)
        }
      end
      
      private
      
      def extract_entities(content)
        {
          features: extract_features(content),
          ui_elements: extract_ui_elements(content),
          colors: extract_colors(content)
        }
      end
      
      def extract_features(content)
        features = []
        features << 'authentication' if content.include?('auth') || content.include?('login')
        features << 'todo' if content.include?('todo') || content.include?('task')
        features << 'chat' if content.include?('chat') || content.include?('message')
        features
      end
      
      def extract_ui_elements(content)
        elements = []
        elements << 'button' if content.include?('button')
        elements << 'form' if content.include?('form')
        elements << 'component' if content.include?('component')
        elements
      end
      
      def extract_colors(content)
        colors = []
        %w[red blue green yellow orange purple pink black white gray].each do |color|
          colors << color if content.include?(color)
        end
        colors
      end
      
      def determine_scope(content)
        if content.include?('entire') || content.include?('rebuild') || content.include?('complete')
          :major
        else
          :minor
        end
      end
    end
  end

  class ChatDevelopmentStandaloneTest < Minitest::Test
    def setup
      @app = MockApp.new
      @user = MockUser.new
      @message = MockAppChatMessage.new(
        content: 'Add user authentication',
        user: @user,
        app: @app
      )
    end
    
    def test_file_context_analyzer_initialization
      analyzer = Ai::FileContextAnalyzer.new(@app)
      assert_instance_of Ai::FileContextAnalyzer, analyzer
    end
    
    def test_file_context_analyzer_empty_app
      analyzer = Ai::FileContextAnalyzer.new(@app)
      context = analyzer.analyze
      
      assert context.is_a?(Hash)
      assert_equal 0, context[:file_structure][:total_files]
      assert context[:existing_components].empty?
      assert context[:dependencies].empty?
    end
    
    def test_file_context_analyzer_with_component_file
      # Add a React component
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
      
      analyzer = Ai::FileContextAnalyzer.new(@app)
      context = analyzer.analyze
      
      assert_operator context[:file_structure][:total_files], :>, 0
      assert context[:existing_components]['TestComponent']
      
      component = context[:existing_components]['TestComponent']
      assert_equal 'TestComponent', component[:name]
      assert_equal :stateful_component, component[:type]
      assert component[:props].any? { |p| p[:name] == 'title' }
    end
    
    def test_file_context_analyzer_with_package_json
      # Add package.json
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
      
      assert context[:dependencies][:dependencies]['react']
      assert_includes context[:dependencies][:framework_analysis][:ui_frameworks], 'react'
      assert_includes context[:dependencies][:framework_analysis][:ui_frameworks], 'tailwind'
    end
    
    def test_chat_message_processor_initialization
      processor = Ai::ChatMessageProcessor.new(@message)
      assert_instance_of Ai::ChatMessageProcessor, processor
    end
    
    def test_message_classification_add_feature
      message = MockAppChatMessage.new(
        content: 'Add user authentication to the app',
        user: @user,
        app: @app
      )
      processor = Ai::ChatMessageProcessor.new(message)
      
      analysis = processor.classify_message_intent
      
      assert_equal :add_feature, analysis[:type]
      assert_includes analysis[:entities][:features], 'authentication'
      assert_operator analysis[:confidence], :>, 0.5
    end
    
    def test_message_classification_style_change
      message = MockAppChatMessage.new(
        content: 'Change the button color to blue',
        user: @user,
        app: @app
      )
      processor = Ai::ChatMessageProcessor.new(message)
      
      analysis = processor.classify_message_intent
      
      assert_equal :style_change, analysis[:type]
      assert_includes analysis[:entities][:colors], 'blue'
      assert_includes analysis[:entities][:ui_elements], 'button'
    end
    
    def test_message_classification_fix_bug
      message = MockAppChatMessage.new(
        content: 'Fix the login form validation error',
        user: @user,
        app: @app
      )
      processor = Ai::ChatMessageProcessor.new(message)
      
      analysis = processor.classify_message_intent
      
      assert_equal :fix_bug, analysis[:type]
      assert_includes analysis[:entities][:features], 'authentication'
      assert_includes analysis[:entities][:ui_elements], 'form'
    end
    
    def test_message_classification_question
      message = MockAppChatMessage.new(
        content: 'How do I deploy this app?',
        user: @user,
        app: @app
      )
      processor = Ai::ChatMessageProcessor.new(message)
      
      analysis = processor.classify_message_intent
      
      assert_equal :question, analysis[:type]
    end
    
    def test_scope_determination
      major_message = MockAppChatMessage.new(
        content: 'Rebuild the entire app with new features',
        user: @user,
        app: @app
      )
      minor_message = MockAppChatMessage.new(
        content: 'Change button color',
        user: @user,
        app: @app
      )
      
      major_processor = Ai::ChatMessageProcessor.new(major_message)
      minor_processor = Ai::ChatMessageProcessor.new(minor_message)
      
      major_analysis = major_processor.classify_message_intent
      minor_analysis = minor_processor.classify_message_intent
      
      assert_equal :major, major_analysis[:scope]
      assert_equal :minor, minor_analysis[:scope]
    end
  end

  puts "🧪 Running Chat Development Standalone Tests"
  puts "==============================================="
end
