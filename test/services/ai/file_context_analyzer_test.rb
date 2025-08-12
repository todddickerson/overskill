require 'test_helper'

class Ai::FileContextAnalyzerTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      email: "test-#{Time.current.to_i}@example.com",
      password: "SecureTestPassword123!"
    )
    
    @team = Team.create!(name: "Test Team #{Time.current.to_i}")
    
    @membership = @team.memberships.create!(
      user: @user,
      role_ids: ['admin']
    )
    
    @app = App.create!(
      name: "Test App #{Time.current.to_i}",
      slug: "test-app-#{Time.current.to_i}",
      team: @team,
      creator: @membership,
      prompt: "Test app prompt"
    )
    
    # Clear existing files for clean test
    @app.app_files.destroy_all
  end
  
  test "analyzes empty app correctly" do
    analyzer = Ai::FileContextAnalyzer.new(@app)
    context = analyzer.analyze
    
    assert_equal 0, context[:file_structure][:total_files]
    assert_empty context[:existing_components]
    assert_empty context[:dependencies]
  end
  
  test "builds file tree structure" do
    create_test_files
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    structure = analyzer.send(:build_file_tree)
    
    assert_operator structure[:total_files], :>, 0
    assert structure[:by_type]['typescript'].present?
    assert structure[:by_directory]['src/components'].present?
    assert structure[:framework_files].include?('package.json')
    assert structure[:app_files].include?('src/components/TestComponent.tsx')
  end
  
  test "identifies and analyzes components" do
    create_test_component
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    components = analyzer.send(:identify_existing_components)
    
    assert components['TestComponent'].present?
    
    component = components['TestComponent']
    assert_equal 'TestComponent', component[:name]
    assert_equal :stateful_component, component[:type]
    assert component[:props].any? { |p| p[:name] == 'title' }
    assert component[:props].any? { |p| p[:name] == 'optional' }
    assert_includes component[:ui_framework], 'tailwind'
    assert_includes component[:state_management], 'useState'
  end
  
  test "extracts component props correctly" do
    content = <<~TSX
      interface ComponentProps {
        title: string;
        count?: number;
        items: string[];
        callback: (value: string) => void;
      }
      
      function Component({ title, count, items, callback }: ComponentProps) {
        return <div>{title}</div>;
      }
    TSX
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    props = analyzer.send(:extract_component_props, content)
    
    assert_equal 4, props.count
    
    title_prop = props.find { |p| p[:name] == 'title' }
    assert_equal 'string', title_prop[:type]
    assert_not title_prop[:optional]
    
    count_prop = props.find { |p| p[:name] == 'count' }
    assert count_prop[:optional]
  end
  
  test "analyzes imports and dependencies" do
    content = <<~TSX
      import React, { useState, useEffect } from 'react';
      import { Button } from '@/components/ui/button';
      import axios from 'axios';
      import './component.css';
      
      export default function Component() {
        return <div>Test</div>;
      }
    TSX
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    imports = analyzer.send(:extract_imports, content)
    
    assert_equal 4, imports.count
    
    react_import = imports.find { |i| i[:package] == 'react' }
    assert_equal :npm_package, react_import[:type]
    
    ui_import = imports.find { |i| i[:package] == '@/components/ui/button' }
    assert_equal :local, ui_import[:type]
    
    axios_import = imports.find { |i| i[:package] == 'axios' }
    assert_equal :npm_package, axios_import[:type]
    
    css_import = imports.find { |i| i[:package] == './component.css' }
    assert_equal :local, css_import[:type]
  end
  
  test "infers component purpose from content and path" do
    analyzer = Ai::FileContextAnalyzer.new(@app)
    
    # Test auth component
    auth_purposes = analyzer.send(:infer_component_purpose, 
      "function Login() { return <form>login</form>; }", 
      "src/components/auth/Login.tsx"
    )
    assert_includes auth_purposes, 'authentication'
    
    # Test todo component
    todo_purposes = analyzer.send(:infer_component_purpose,
      "function TodoList() { return <div>tasks</div>; }",
      "src/components/TodoList.tsx"
    )
    assert_includes todo_purposes, 'task_management'
    
    # Test chat component
    chat_purposes = analyzer.send(:infer_component_purpose,
      "function Chat() { return <div>messages</div>; }",
      "src/components/Chat.tsx"
    )
    assert_includes chat_purposes, 'messaging'
  end
  
  test "calculates component complexity" do
    analyzer = Ai::FileContextAnalyzer.new(@app)
    
    # Simple component
    simple_content = "function Simple() { return <div>Hello</div>; }"
    simple_complexity = analyzer.send(:calculate_component_complexity, simple_content)
    assert_equal :simple, simple_complexity
    
    # Complex component
    complex_content = <<~TSX
      function Complex() {
        const [state1, setState1] = useState(null);
        const [state2, setState2] = useState([]);
        const [state3, setState3] = useState({});
        
        useEffect(() => {
          // Complex logic
        }, []);
        
        const handleClick = () => {
          if (condition) {
            // More logic
          }
          
          switch (type) {
            case 'A': return processA();
            case 'B': return processB();
          }
        };
        
        return (
          <div>
            {items.map(item => 
              item.active ? <ActiveItem key={item.id} /> : null
            )}
            {data.filter(d => d.visible).map(d => <Item key={d.id} />)}
          </div>
        );
      }
    TSX
    
    complex_complexity = analyzer.send(:calculate_component_complexity, complex_content)
    assert_equal :complex, complex_complexity
  end
  
  test "assesses component reusability" do
    analyzer = Ai::FileContextAnalyzer.new(@app)
    
    # Highly reusable UI component
    reusable_content = <<~TSX
      interface ButtonProps {
        children: React.ReactNode;
        variant: 'primary' | 'secondary';
        onClick: () => void;
      }
      
      export function Button({ children, variant, onClick }: ButtonProps) {
        return (
          <button className={`btn btn-${variant}`} onClick={onClick}>
            {children}
          </button>
        );
      }
    TSX
    
    reusability = analyzer.send(:assess_reusability, reusable_content, 'src/components/ui/Button.tsx')
    assert_equal :high, reusability
    
    # Low reusability business logic component
    specific_content = <<~TSX
      export function UserDashboard() {
        const user = getCurrentUser();
        const orders = fetchUserOrders(user.id);
        
        return (
          <div>
            <h1>Welcome, {user.name}!</h1>
            <p>Your account balance: $1,234.56</p>
            <div>Your recent orders...</div>
          </div>
        );
      }
    TSX
    
    low_reusability = analyzer.send(:assess_reusability, specific_content, 'src/pages/UserDashboard.tsx')
    assert_equal :low, low_reusability
  end
  
  test "detects UI frameworks" do
    analyzer = Ai::FileContextAnalyzer.new(@app)
    
    # Tailwind CSS
    tailwind_content = 'className="bg-blue-500 text-white p-4 hover:bg-blue-600"'
    frameworks = analyzer.send(:detect_ui_framework, tailwind_content)
    assert_includes frameworks, 'tailwind'
    
    # shadcn/ui
    shadcn_content = 'import { Button } from "@/components/ui/button"'
    frameworks = analyzer.send(:detect_ui_framework, shadcn_content)
    assert_includes frameworks, 'shadcn_ui'
    
    # React Router
    router_content = 'import { useNavigate } from "react-router-dom"'
    frameworks = analyzer.send(:detect_ui_framework, router_content)
    assert_includes frameworks, 'react_router'
  end
  
  test "parses package.json dependencies" do
    package_content = {
      "dependencies" => {
        "react" => "^18.2.0",
        "react-router-dom" => "^6.8.0",
        "@supabase/supabase-js" => "^2.39.0",
        "tailwindcss" => "^3.4.0"
      },
      "devDependencies" => {
        "vite" => "^5.0.0",
        "@types/react" => "^18.0.0"
      },
      "scripts" => {
        "dev" => "vite",
        "build" => "vite build"
      }
    }.to_json
    
    @app.app_files.create!(
      path: 'package.json',
      content: package_content,
      team: @team
    )
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    dependencies = analyzer.send(:parse_package_json)
    
    assert dependencies[:dependencies]['react'].present?
    assert dependencies[:dev_dependencies]['vite'].present?
    assert dependencies[:scripts]['dev'].present?
    
    framework_analysis = dependencies[:framework_analysis]
    assert_includes framework_analysis[:ui_frameworks], 'react'
    assert_includes framework_analysis[:ui_frameworks], 'tailwind'
    assert_includes framework_analysis[:database], 'supabase'
    assert_includes framework_analysis[:build_tools], 'vite'
  end
  
  test "analyzes routing structure" do
    router_content = <<~TSX
      import { BrowserRouter, Routes, Route } from 'react-router-dom';
      import Home from './pages/Home';
      import Login from './pages/auth/Login';
      import Dashboard from './pages/Dashboard';
      import ProtectedRoute from './components/ProtectedRoute';
      
      export default function AppRouter() {
        return (
          <BrowserRouter>
            <Routes>
              <Route path="/" element={<Home />} />
              <Route path="/login" element={<Login />} />
              <Route path="/dashboard" element={
                <ProtectedRoute>
                  <Dashboard />
                </ProtectedRoute>
              } />
            </Routes>
          </BrowserRouter>
        );
      }
    TSX
    
    @app.app_files.create!(
      path: 'src/router.tsx',
      content: router_content,
      team: @team
    )
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    routing = analyzer.send(:analyze_routing_structure)
    
    assert_equal 3, routing[:total_routes]
    assert_equal 'react_router_browser', routing[:router_type]
    
    home_route = routing[:routes].find { |r| r[:path] == '/' }
    assert_equal 'Home', home_route[:component]
    assert_equal :public, home_route[:type]
    
    dashboard_route = routing[:routes].find { |r| r[:path] == '/dashboard' }
    assert_equal 'Dashboard', dashboard_route[:component]
    assert dashboard_route[:protected]
  end
  
  test "infers database schema from code" do
    # Create files with database interactions
    component_content = <<~TSX
      import { db } from '@/lib/app-scoped-db';
      
      export default function TodoList() {
        const [todos, setTodos] = useState([]);
        
        useEffect(() => {
          db.from('todos').select('*').then(setTodos);
        }, []);
        
        const addTodo = (text) => {
          db.from('todos').insert({ text, completed: false });
        };
        
        const updateTodo = (id, updates) => {
          db.from('todos').update(updates).eq('id', id);
        };
        
        return <div>Todo List</div>;
      }
    TSX
    
    @app.app_files.create!(
      path: 'src/components/TodoList.tsx',
      content: component_content,
      team: @team
    )
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    schema = analyzer.send(:infer_database_schema)
    
    assert schema[:tables]['todos'].present?
    
    todos_table = schema[:tables]['todos']
    assert_includes todos_table[:operations], 'select'
    assert_includes todos_table[:operations], 'insert'
    assert_includes todos_table[:operations], 'update'
    assert_equal 'task_management', todos_table[:inferred_purpose]
    assert_operator todos_table[:usage_count], :>, 0
  end
  
  test "generates improvement suggestions" do
    # Test with minimal app
    analyzer = Ai::FileContextAnalyzer.new(@app)
    suggestions = analyzer.send(:generate_improvement_suggestions)
    
    # Should suggest adding components for small apps
    expansion_suggestion = suggestions.find { |s| s[:type] == 'expansion' }
    assert expansion_suggestion.present?
    
    # Should suggest authentication if missing
    auth_suggestion = suggestions.find { |s| s[:type] == 'feature_addition' && s[:suggestion].include?('authentication') }
    assert auth_suggestion.present?
  end
  
  test "handles analysis errors gracefully" do
    # Create invalid JSON in package.json
    @app.app_files.create!(
      path: 'package.json',
      content: 'invalid json content',
      team: @team
    )
    
    analyzer = Ai::FileContextAnalyzer.new(@app)
    
    assert_nothing_raised "Should handle invalid JSON gracefully" do
      dependencies = analyzer.send(:parse_package_json)
      assert_empty dependencies
    end
  end
  
  private
  
  def create_test_files
    # Create package.json
    @app.app_files.create!(
      path: 'package.json',
      content: '{"name": "test-app", "dependencies": {"react": "^18.0.0"}}',
      team: @team
    )
    
    # Create a component
    create_test_component
    
    # Create a page
    @app.app_files.create!(
      path: 'src/pages/Home.tsx',
      content: 'export default function Home() { return <div>Home</div>; }',
      team: @team
    )
  end
  
  def create_test_component
    component_content = <<~TSX
      import React, { useState, useEffect } from 'react';
      import { Button } from '@/components/ui/button';
      
      interface TestComponentProps {
        title: string;
        optional?: boolean;
        items: string[];
      }
      
      export default function TestComponent({ title, optional, items }: TestComponentProps) {
        const [count, setCount] = useState(0);
        const [loading, setLoading] = useState(false);
        
        useEffect(() => {
          console.log('Component mounted');
        }, []);
        
        const handleClick = () => {
          if (count > 10) {
            setLoading(true);
          }
          setCount(prev => prev + 1);
        };
        
        return (
          <div className="bg-blue-500 text-white p-4 hover:bg-blue-600">
            <h1 className="text-xl font-bold">{title}</h1>
            {optional && <p>Optional content</p>}
            <Button onClick={handleClick} variant="primary">
              Count: {count}
            </Button>
            {loading && <div>Loading...</div>}
            <ul>
              {items.map((item, index) => (
                <li key={index}>{item}</li>
              ))}
            </ul>
          </div>
        );
      }
    TSX
    
    @app.app_files.create!(
      path: 'src/components/TestComponent.tsx',
      content: component_content,
      team: @team
    )
  end
end