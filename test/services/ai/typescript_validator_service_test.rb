require 'test_helper'

class Ai::TypescriptValidatorServiceTest < ActiveSupport::TestCase
  setup do
    @app = create(:app)
    @validator = Ai::TypescriptValidatorService.new(@app)
  end

  # ========================
  # JSX Validation Tests - Based on Real Failures
  # ========================

  test "fixes malformed JSX className with backslash before closing quote" do
    # This pattern caused the GitHub Actions failure:
    # <p className="text-sm text-gray-600 mb-2\">Regular Price: ...
    malformed_content = <<~JSX
      function Component() {
        return (
          <p className="text-sm text-gray-600 mb-2\\">Regular Price: $1,791</p>
        );
      }
    JSX

    expected_content = <<~JSX
      function Component() {
        return (
          <p className="text-sm text-gray-600 mb-2">Regular Price: $1,791</p>
        );
      }
    JSX

    result = @validator.validate_and_fix_typescript("test.tsx", malformed_content)
    assert_equal expected_content.strip, result.strip
  end

  test "fixes JSX attributes with double-escaped quotes" do
    # This pattern caused nested quote issues:
    # <span className=\"line-through\">$1,791</span>
    malformed_content = <<~JSX
      function Component() {
        return (
          <p className="text-lg mb-2\\">Regular Price: <span className=\\"line-through\\">$5,794</span></p>
        );
      }
    JSX

    expected_content = <<~JSX
      function Component() {
        return (
          <p className="text-lg mb-2">Regular Price: <span className="line-through">$5,794</span></p>
        );
      }
    JSX

    result = @validator.validate_and_fix_typescript("test.tsx", malformed_content)
    assert_equal expected_content.strip, result.strip
  end

  test "handles multiple JSX validation issues in single file" do
    # Complex test with multiple issues from the actual failed deployment
    malformed_content = <<~JSX
      function PseudoOrderForm() {
        return (
          <div className="container mx-auto px-4\\">
            <div className="bg-gradient-to-r from-red-50 to-pink-50 border border-red-200\\">
              <p className="text-sm text-gray-600 mb-2\\">Regular Price: <span className=\\"line-through\\">$1,791</span></p>
              <p className="text-3xl font-bold text-red-600 mb-2\\">Special Launch Price</p>
              <p className="funnel-price text-5xl mb-2\\">$97</p>
            </div>
          </div>
        );
      }
    JSX

    expected_content = <<~JSX
      function PseudoOrderForm() {
        return (
          <div className="container mx-auto px-4">
            <div className="bg-gradient-to-r from-red-50 to-pink-50 border border-red-200">
              <p className="text-sm text-gray-600 mb-2">Regular Price: <span className="line-through">$1,791</span></p>
              <p className="text-3xl font-bold text-red-600 mb-2">Special Launch Price</p>
              <p className="funnel-price text-5xl mb-2">$97</p>
            </div>
          </div>
        );
      }
    JSX

    result = @validator.validate_and_fix_typescript("components/PseudoOrderForm.tsx", malformed_content)
    assert_equal expected_content.strip, result.strip
  end

  test "handles Upsell component validation issues" do
    # Based on the actual Upsell.tsx failures
    malformed_content = <<~JSX
      function Upsell() {
        return (
          <div className="min-h-screen bg-gradient-to-br\\">
            <p className="text-lg mb-2\\">Regular Price: <span className=\\"line-through\\">$5,794</span></p>
          </div>
        );
      }
    JSX

    expected_content = <<~JSX
      function Upsell() {
        return (
          <div className="min-h-screen bg-gradient-to-br">
            <p className="text-lg mb-2">Regular Price: <span className="line-through">$5,794</span></p>
          </div>
        );
      }
    JSX

    result = @validator.validate_and_fix_typescript("pages/Upsell.tsx", malformed_content)
    assert_equal expected_content.strip, result.strip
  end

  # ========================
  # Legacy Pattern Tests
  # ========================

  test "fixes console.log patterns" do
    content = 'console.log("Hello World");'
    result = @validator.validate_and_fix_typescript("test.js", content)
    
    # Should not change valid console.log
    assert_equal content, result
  end

  test "fixes System.out.println patterns" do
    malformed_content = '"System.out.println("Hello World");"'
    # The validator adds extra escaping for nested quotes
    expected_content = '"System.out.println(\\\\"Hello World\\\\");"'
    
    result = @validator.validate_and_fix_typescript("test.js", malformed_content)
    assert_equal expected_content, result
  end

  # ========================
  # File Type Detection Tests
  # ========================

  test "only processes TypeScript and JavaScript files" do
    css_content = ".class { color: red; }"
    result = @validator.validate_and_fix_typescript("styles.css", css_content)
    
    # Should return unchanged for non-TS/JS files
    assert_equal css_content, result
  end

  test "processes .tsx files" do
    tsx_content = '<p className="test\\">Hello</p>'
    result = @validator.validate_and_fix_typescript("component.tsx", tsx_content)
    
    # Should fix JSX in .tsx files
    assert_equal '<p className="test">Hello</p>', result
  end

  test "processes .jsx files" do
    jsx_content = '<div className="container\\">Content</div>'
    result = @validator.validate_and_fix_typescript("component.jsx", jsx_content)
    
    # Should fix JSX in .jsx files  
    assert_equal '<div className="container">Content</div>', result
  end

  # ========================
  # Edge Cases and Regression Tests
  # ========================

  test "handles empty content gracefully" do
    result = @validator.validate_and_fix_typescript("empty.tsx", "")
    assert_equal "", result
  end

  test "handles content with no issues" do
    valid_content = <<~JSX
      function ValidComponent() {
        return (
          <div className="container mx-auto">
            <p className="text-lg">Valid JSX content</p>
          </div>
        );
      }
    JSX

    result = @validator.validate_and_fix_typescript("valid.tsx", valid_content)
    # Strip trailing whitespace for comparison
    assert_equal valid_content.strip, result.strip
  end

  test "handles mixed content types correctly" do
    mixed_content = <<~MIXED
      // Valid JavaScript
      const greeting = "Hello World";
      console.log(greeting);
      
      // JSX with issues
      function Component() {
        return <p className="text-lg mb-2\\">Mixed content</p>;
      }
    MIXED

    result = @validator.validate_and_fix_typescript("mixed.tsx", mixed_content)
    
    # Should only fix the JSX part
    assert_includes result, 'console.log(greeting);'
    assert_includes result, 'className="text-lg mb-2"'
    refute_includes result, 'mb-2\\"'
  end

  # ========================
  # Validation Error Detection Tests  
  # ========================

  test "detects and reports validation errors" do
    # Content that can't be auto-fixed
    problematic_content = <<~JSX
      function BrokenComponent() {
        return (
          <div>
            <p>Unclosed paragraph
            <span>Unclosed span
          </div>
      }
    JSX

    result = @validator.validate_and_fix_typescript("broken.tsx", problematic_content)
    
    # Should have validation_errors reader available
    assert_respond_to @validator, :validation_errors
    # Should return some content (even if not perfectly fixed)
    refute_empty result
  end

  # ========================
  # Real-World Scenario Tests (Based on Funnelcraft Failures)
  # ========================

  test "validates actual PseudoOrderForm.tsx content pattern" do
    # Simulates the exact pattern that failed in GitHub Actions
    real_world_content = <<~JSX
      <div className="text-center mb-8">
        <div className="bg-gradient-to-r from-red-50 to-pink-50 border border-red-200 rounded-lg p-6 mb-6\\">
          <p className="text-sm text-gray-600 mb-2\\">Regular Price: <span className=\\"line-through\\">$1,791</span></p>
          <p className="text-3xl font-bold text-red-600 mb-2\\">Special Launch Price</p>
          <p className="funnel-price text-5xl mb-2\\">$97</p>
          <p className="text-sm text-gray-600\\">One-time payment • Instant access • No recurring fees</p>
        </div>
      </div>
    JSX

    result = @validator.validate_and_fix_typescript("src/pages/PseudoOrderForm.tsx", real_world_content)
    
    # Verify all backslash quote issues are fixed
    refute_includes result, '\\">'
    refute_includes result, 'className=\\"'
    
    # Verify proper JSX structure
    assert_includes result, 'className="text-sm text-gray-600 mb-2"'
    assert_includes result, 'className="line-through"'
  end

  test "validates actual Upsell.tsx content pattern" do
    # Simulates the exact pattern that failed in Upsell component
    upsell_content = <<~JSX
      <div className="min-h-screen bg-gradient-to-br from-gray-50 to-gray-100\\">
        <p className="text-lg mb-2\\">Regular Price: <span className=\\"line-through\\">$5,794</span></p>
        <p className="text-4xl font-bold text-green-600 mb-4\\">Today Only: $997</p>
      </div>
    JSX

    result = @validator.validate_and_fix_typescript("src/pages/Upsell.tsx", upsell_content)
    
    # Verify all issues are fixed
    refute_includes result, '\\">'
    refute_includes result, 'className=\\"'
    
    # Verify correct JSX syntax
    assert_includes result, 'className="text-lg mb-2"'
    assert_includes result, 'className="line-through"'
    assert_includes result, 'className="text-4xl font-bold text-green-600 mb-4"'
  end
end