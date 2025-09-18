require "test_helper"

module Ai
  class CodeValidatorServiceTest < ActiveSupport::TestCase
    test "validates files with forbidden ES6 imports" do
      files = [
        {
          path: "app.js",
          content: "import React from 'react';\nimport ReactDOM from 'react-dom';",
          type: "javascript"
        }
      ]

      result = CodeValidatorService.validate_files(files)

      assert_not result[:valid]
      assert_equal 2, result[:errors].size
      assert_match(/ES6 import statements are not allowed/, result[:errors].first[:message])
    end

    test "validates files with forbidden require calls" do
      files = [
        {
          path: "app.js",
          content: "const fs = require('fs');\nconst path = require('path');",
          type: "javascript"
        }
      ]

      result = CodeValidatorService.validate_files(files)

      assert_not result[:valid]
      assert result[:errors].size >= 1  # At least one error for require()
      assert_match(/CommonJS require\(\) is not allowed/, result[:errors].first[:message])
    end

    test "validates files with JSX syntax" do
      files = [
        {
          path: "app.js",
          content: "function App() { return <div>Hello</div>; }",
          type: "javascript"
        }
      ]

      result = CodeValidatorService.validate_files(files)

      assert_not result[:valid]
      assert result[:errors].any? { |e| e[:message].include?("JSX") }
    end

    test "passes validation for browser-compatible React code" do
      files = [
        {
          path: "app.js",
          content: <<~JS,
            const { useState, useEffect } = React;
            
            function App() {
              const [count, setCount] = useState(0);
              
              return React.createElement('div', null,
                React.createElement('h1', null, 'Count: ', count),
                React.createElement('button', { onClick: () => setCount(count + 1) }, 'Increment')
              );
            }
            
            const root = ReactDOM.createRoot(document.getElementById('root'));
            root.render(React.createElement(App));
          JS
          type: "javascript"
        }
      ]

      result = CodeValidatorService.validate_files(files)

      assert result[:valid]
      assert_empty result[:errors]
    end

    test "fixes common ES6 import issues" do
      content = <<~JS
        import React from 'react';
        import ReactDOM from 'react-dom';
        
        export default function App() {
          return <div>Hello</div>;
        }
        
        export { App };
      JS

      fixed = CodeValidatorService.fix_common_issues(content, "javascript")

      assert_match(/const { useState, useEffect, useRef } = React;/, fixed)
      assert_no_match(/import React/, fixed)
      assert_no_match(/import ReactDOM/, fixed)
      assert_match(/window.App = function/, fixed)
      assert_no_match(/export { App }/, fixed)
    end

    test "validates HTML files for proper React CDN loading" do
      files = [
        {
          path: "index.html",
          content: <<~HTML,
            <!DOCTYPE html>
            <html>
            <body>
              <div id="root"></div>
              <script src="app.js"></script>
            </body>
            </html>
          HTML
          type: "html"
        }
      ]

      result = CodeValidatorService.validate_files(files)

      # Should be valid since missing React CDN is a warning, not an error
      assert result[:valid]
      # Should have warning about React CDN
      assert result[:warnings].present?
      assert result[:warnings].any? { |w| w[:message].include?("React from CDN") }
    end

    test "validates script loading order in HTML" do
      files = [
        {
          path: "index.html",
          content: <<~HTML,
            <!DOCTYPE html>
            <html>
            <body>
              <script src="app.js"></script>
              <script src="components.js"></script>
            </body>
            </html>
          HTML
          type: "html"
        }
      ]

      result = CodeValidatorService.validate_files(files)

      assert_not result[:valid]
      assert result[:errors].any? { |e| e[:message].include?("components.js must be loaded before app.js") }
    end
  end
end
