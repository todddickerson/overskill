require "test_helper"

class Deployment::AutoFixServiceTest < ActiveSupport::TestCase
  setup do
    @app = create(:app)
    @auto_fix = Deployment::AutoFixService.new(@app)

    # Create test app files
    @test_file = @app.app_files.create!(
      path: "src/components/TestComponent.tsx",
      content: test_component_content,
      team: @app.team
    )

    @sales_page_file = @app.app_files.create!(
      path: "src/pages/SalesPage.tsx",
      content: sales_page_content,
      team: @app.team
    )
  end

  # ========================
  # JSX Tag Mismatch Fix Tests
  # ========================

  test "fixes JSX tag mismatch errors" do
    error = {
      type: :jsx_tag_mismatch,
      file: "src/components/TestComponent.tsx",
      line: 5,
      column: 10,
      closing_tag: "span",
      opening_tag: "div",
      message: "Unexpected closing 'span' tag does not match opening 'div' tag"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Fixed JSX tag mismatch"
    assert_equal 1, result[:changes].length

    # Verify the file was updated
    @test_file.reload
    refute_includes @test_file.content, "</span>"
    assert_includes @test_file.content, "</div>"
  end

  test "fixes duplicate div tag issues" do
    # Create a file with duplicate div tags
    @app.app_files.create!(
      path: "src/components/Calculator.tsx",
      content: <<~JSX,
        function Calculator() {
          return (
            <div className="calculator">
              <Button>Click me</Button>
              </div>
            </div>
          );
        }
      JSX
      team: @app.team
    )

    error = {
      type: :jsx_tag_mismatch,
      file: "src/components/Calculator.tsx",
      line: 5,
      column: 10,
      closing_tag: "div",
      opening_tag: "div",
      message: "Extra div closing tag detected"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Removed duplicate div closing tags"
  end

  # ========================
  # JSX Unclosed Tag Fix Tests
  # ========================

  test "fixes JSX unclosed tag errors" do
    error = {
      type: :jsx_unclosed_tag,
      file: "src/components/TestComponent.tsx",
      line: 4,
      column: 8,
      tag_name: "section",
      message: "JSX element 'section' has no corresponding closing tag"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Added missing closing tag </section>"
    assert_equal 1, result[:changes].length

    # Verify the closing tag was added
    @test_file.reload
    assert_includes @test_file.content, "</section>"
  end

  # ========================
  # JSX Expression Error Fix Tests
  # ========================

  test "fixes JSX expression errors in className attributes" do
    # Create file with malformed className
    expression_error_file = @app.app_files.create!(
      path: "src/components/BadClassName.tsx",
      content: <<~JSX,
        function Component() {
          return (
            <div className="container mx-auto\\">
              <p>Content</p>
            </div>
          );
        }
      JSX
      team: @app.team
    )

    error = {
      type: :jsx_expression_error,
      file: "src/components/BadClassName.tsx",
      line: 3,
      column: 15,
      message: "JSX expression error in className attribute"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Fixed JSX expression error in className/style attribute"

    # Verify the fix
    expression_error_file.reload
    assert_includes expression_error_file.content, 'className="container mx-auto"'
    refute_includes expression_error_file.content, 'className="container mx-auto\\"'
  end

  test "fixes JSX expression errors in style attributes" do
    style_error_file = @app.app_files.create!(
      path: "src/components/BadStyle.tsx",
      content: <<~JSX,
        function Component() {
          return (
            <div style="color: red\\">
              <p>Content</p>
            </div>
          );
        }
      JSX
      team: @app.team
    )

    error = {
      type: :jsx_expression_error,
      file: "src/components/BadStyle.tsx",
      line: 3,
      column: 15,
      message: "JSX expression error in style attribute"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    style_error_file.reload
    assert_includes style_error_file.content, 'style="color: red"'
  end

  # ========================
  # Unterminated String Fix Tests
  # ========================

  test "fixes unterminated string literals in JSX attributes" do
    unterminated_file = @app.app_files.create!(
      path: "src/components/UnterminatedString.tsx",
      content: <<~JSX,
        function Component() {
          return (
            <div className="container mx-auto>
              <p>Content</p>
            </div>
          );
        }
      JSX
      team: @app.team
    )

    error = {
      type: :unterminated_string,
      file: "src/components/UnterminatedString.tsx",
      line: 3,
      column: 25,
      message: "Unterminated string literal"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Added missing closing quote"

    unterminated_file.reload
    assert_includes unterminated_file.content, 'className="container mx-auto"'
  end

  test "fixes generic unterminated strings" do
    generic_unterminated_file = @app.app_files.create!(
      path: "src/utils/constants.ts",
      content: <<~TS,
        const greeting = "Hello World
        const farewell = "Goodbye";
      TS
      team: @app.team
    )

    error = {
      type: :unterminated_string,
      file: "src/utils/constants.ts",
      line: 1,
      column: 30,
      message: "Unterminated string literal"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    generic_unterminated_file.reload
    assert_includes generic_unterminated_file.content, '"Hello World"'
  end

  # ========================
  # Unexpected Token Fix Tests
  # ========================

  test "fixes unexpected token errors with missing closing braces" do
    brace_error_file = @app.app_files.create!(
      path: "src/hooks/useData.ts",
      content: <<~TS,
        function useData() {
          const data = { name: "test", value: 42
          return data;
        }
      TS
      team: @app.team
    )

    error = {
      type: :unexpected_token,
      file: "src/hooks/useData.ts",
      line: 2,
      column: 45,
      message: "Unexpected token, missing '}'"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Fixed unexpected token by balancing braces"

    brace_error_file.reload
    assert_includes brace_error_file.content, '{ name: "test", value: 42 }'
  end

  test "fixes unexpected token errors with extra closing braces" do
    extra_brace_file = @app.app_files.create!(
      path: "src/utils/helper.ts",
      content: <<~TS,
        function helper() {
          return true;
        }}
      TS
      team: @app.team
    )

    error = {
      type: :unexpected_token,
      file: "src/utils/helper.ts",
      line: 3,
      column: 3,
      message: "Unexpected token '}'"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    extra_brace_file.reload
    refute_includes extra_brace_file.content, "}}"
  end

  # ========================
  # Missing Semicolon Fix Tests
  # ========================

  test "fixes missing semicolon errors" do
    semicolon_file = @app.app_files.create!(
      path: "src/types/index.ts",
      content: <<~TS,
        const API_URL = "https://api.example.com"
        const VERSION = "1.0.0";
      TS
      team: @app.team
    )

    error = {
      type: :missing_semicolon,
      file: "src/types/index.ts",
      line: 1,
      column: 42,
      message: "';' expected"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Added missing semicolon"

    semicolon_file.reload
    assert_includes semicolon_file.content, 'const API_URL = "https://api.example.com";'
  end

  test "does not add semicolon to lines ending with braces" do
    @app.app_files.create!(
      path: "src/components/Component.tsx",
      content: <<~TS,
        function Component() {
          return <div>Content</div>;
        }
      TS
      team: @app.team
    )

    error = {
      type: :missing_semicolon,
      file: "src/components/Component.tsx",
      line: 3,
      column: 2,
      message: "';' expected"
    }

    result = @auto_fix.apply_fix(error)

    # Should not succeed because line ends with }
    refute result[:success]
  end

  # ========================
  # Missing Parenthesis Fix Tests
  # ========================

  test "fixes missing closing parenthesis errors" do
    parenthesis_file = @app.app_files.create!(
      path: "src/utils/calculator.ts",
      content: <<~TS,
        function calculate(a: number, b: number) {
          return Math.max(a, b;
        }
      TS
      team: @app.team
    )

    error = {
      type: :missing_parenthesis,
      file: "src/utils/calculator.ts",
      line: 2,
      column: 22,
      message: "')' expected"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Added missing closing parenthesis"

    parenthesis_file.reload
    assert_includes parenthesis_file.content, "Math.max(a, b);"
  end

  # ========================
  # Import/Module Error Fix Tests
  # ========================

  test "fixes import errors by adding missing file extensions" do
    import_file = @app.app_files.create!(
      path: "src/pages/Home.tsx",
      content: <<~TS,
        import { Button } from './components/Button';
        import { Header } from './components/Header';
      TS
      team: @app.team
    )

    # Create the target files that should exist
    @app.app_files.create!(
      path: "src/pages/components/Button.tsx",
      content: "export const Button = () => <button />;",
      team: @app.team
    )

    error = {
      type: :missing_import,
      file: "src/pages/Home.tsx",
      line: 1,
      column: 1,
      module_name: "./components/Button",
      message: "Cannot find module './components/Button' or its corresponding type declarations"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Added missing file extension"

    import_file.reload
    assert_includes import_file.content, "from './components/Button.tsx'"
  end

  # ========================
  # Undefined Variable Fix Tests
  # ========================

  test "fixes undefined React hook variables by adding imports" do
    hook_file = @app.app_files.create!(
      path: "src/hooks/useCounter.tsx",
      content: <<~TS,
        import React from 'react';
        
        function useCounter() {
          const [count, setCount] = useState(0);
          return { count, setCount };
        }
      TS
      team: @app.team
    )

    error = {
      type: :undefined_variable,
      file: "src/hooks/useCounter.tsx",
      line: 4,
      column: 30,
      message: "Cannot find name 'useState'"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Added missing React hook import: useState"

    hook_file.reload
    assert_includes hook_file.content, "import React, { useState } from 'react';"
  end

  test "adds React import when none exists for hooks" do
    no_react_file = @app.app_files.create!(
      path: "src/hooks/useEffect.tsx",
      content: <<~TS,
        function useCustomEffect() {
          useEffect(() => {
            console.log('Effect');
          }, []);
        }
      TS
      team: @app.team
    )

    error = {
      type: :undefined_variable,
      file: "src/hooks/useEffect.tsx",
      line: 2,
      column: 5,
      message: "Cannot find name 'useEffect'"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    no_react_file.reload
    assert_includes no_react_file.content, "import React, { useEffect } from 'react';"
  end

  # ========================
  # JSX Syntax Error Fix Tests
  # ========================

  test "fixes class to className attribute errors" do
    class_attr_file = @app.app_files.create!(
      path: "src/components/OldJSX.tsx",
      content: <<~JSX,
        function Component() {
          return (
            <div class="container">
              <p class="text">Content</p>
            </div>
          );
        }
      JSX
      team: @app.team
    )

    error = {
      type: :jsx_syntax_error,
      file: "src/components/OldJSX.tsx",
      line: 3,
      column: 10,
      message: "Invalid attribute 'class', did you mean 'className'?"
    }

    result = @auto_fix.apply_fix(error)

    assert result[:success]
    assert_includes result[:description], "Changed 'class' attributes to 'className'"

    class_attr_file.reload
    assert_includes class_attr_file.content, 'className="container"'
    assert_includes class_attr_file.content, 'className="text"'
    refute_includes class_attr_file.content, "class="
  end

  # ========================
  # Error Handling Tests
  # ========================

  test "handles file not found errors gracefully" do
    error = {
      type: :jsx_unclosed_tag,
      file: "src/nonexistent/File.tsx",
      line: 10,
      column: 5,
      tag_name: "div"
    }

    result = @auto_fix.apply_fix(error)

    refute result[:success]
    assert_includes result[:error], "File not found"
  end

  test "handles line number out of range errors" do
    error = {
      type: :missing_semicolon,
      file: "src/components/TestComponent.tsx",
      line: 1000, # Way beyond the file length
      column: 5,
      message: "';' expected"
    }

    result = @auto_fix.apply_fix(error)

    refute result[:success]
    assert_includes result[:error], "Line number out of range"
  end

  test "handles unsupported error types" do
    error = {
      type: :unknown_error_type,
      file: "src/components/TestComponent.tsx",
      line: 5,
      column: 10,
      message: "Some unsupported error"
    }

    result = @auto_fix.apply_fix(error)

    refute result[:success]
    assert_includes result[:error], "No fix available for error type"
  end

  test "handles exceptions during fix application" do
    # Mock an error during file update
    error = {
      type: :jsx_unclosed_tag,
      file: "src/components/TestComponent.tsx",
      line: 4,
      column: 8,
      tag_name: "section"
    }

    # Make the app file throw an error when trying to update
    @test_file.stub(:update!, ->(*) { raise StandardError.new("Database error") }) do
      result = @auto_fix.apply_fix(error)

      refute result[:success]
      assert_includes result[:error], "Exception while applying fix"
    end
  end

  private

  def test_component_content
    <<~JSX
      function TestComponent() {
        return (
          <div className="container">
            <section className="hero">
              <h1>Title</h1>
              <p>Content</p>
            </span>
          </div>
        );
      }
    JSX
  end

  def sales_page_content
    <<~JSX
      export default function SalesPage() {
        return (
          <div className="min-h-screen">
            <section className="py-16">
              <div className="container mx-auto px-4">
                <h2 className="text-3xl font-bold">What You'll Get Inside</h2>
              </div>
            </section>
          </div>
        );
      }
    JSX
  end
end
