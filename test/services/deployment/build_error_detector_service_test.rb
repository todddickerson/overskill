require 'test_helper'

class Deployment::BuildErrorDetectorServiceTest < ActiveSupport::TestCase
  setup do
    @app = create(:app)
    @detector = Deployment::BuildErrorDetectorService.new(@app)
  end

  # ========================
  # Modern TypeScript Error Format Tests
  # ========================

  test "detects JSX unclosed tag errors in modern format" do
    log_content = <<~LOG
      ##[error]src/pages/SalesPage.tsx(127,7): error TS2315: JSX element 'section' has no corresponding closing tag.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :jsx_unclosed_tag, error[:type]
    assert_equal "src/pages/SalesPage.tsx", error[:file]
    assert_equal 127, error[:line]
    assert_equal 7, error[:column]
    assert_equal "section", error[:tag_name]
    assert_equal :high, error[:severity]
    assert error[:auto_fixable]
  end

  test "detects JSX tag mismatch errors in modern format" do
    log_content = <<~LOG
      ##[error]src/components/Calculator.tsx(45,12): error TS17008: Unexpected closing 'div' tag does not match opening 'section' tag
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :jsx_tag_mismatch, error[:type]
    assert_equal "src/components/Calculator.tsx", error[:file]
    assert_equal 45, error[:line]
    assert_equal 12, error[:column]
    assert_equal "section", error[:tag_name] # Should extract opening tag name
    assert_equal :high, error[:severity]
    assert error[:auto_fixable]
  end

  test "detects JSX expression errors in modern format" do
    log_content = <<~LOG
      ##[error]src/pages/Home.tsx(23,18): error TS1003: JSX expression expected.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :jsx_expression_error, error[:type]
    assert_equal "src/pages/Home.tsx", error[:file]
    assert_equal 23, error[:line]
    assert_equal 18, error[:column]
    assert_equal :high, error[:severity]
  end

  test "detects unterminated string literal errors" do
    log_content = <<~LOG
      ##[error]src/components/Button.tsx(15,25): error TS1002: Unterminated string literal.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :unterminated_string, error[:type]
    assert_equal "src/components/Button.tsx", error[:file]
    assert_equal 15, error[:line]
    assert_equal 25, error[:column]
    assert_equal :high, error[:severity]
    assert error[:auto_fixable]
  end

  test "detects unexpected token errors" do
    log_content = <<~LOG
      ##[error]src/utils/helpers.tsx(8,32): error TS1109: Unexpected token.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :unexpected_token, error[:type]
    assert_equal "src/utils/helpers.tsx", error[:file]
    assert_equal 8, error[:line]
    assert_equal 32, error[:column]
    assert_equal :high, error[:severity]
    assert error[:auto_fixable]
  end

  test "detects missing parenthesis errors" do
    log_content = <<~LOG
      ##[error]src/hooks/useData.tsx(42,15): error TS1005: ')' expected.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :missing_parenthesis, error[:type]
    assert_equal "src/hooks/useData.tsx", error[:file]
    assert_equal 42, error[:line]
    assert_equal 15, error[:column]
    assert_equal :high, error[:severity]
    assert error[:auto_fixable]
  end

  test "detects missing semicolon errors" do
    log_content = <<~LOG
      ##[error]src/types/index.ts(28,5): error TS1005: ';' expected.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :missing_semicolon, error[:type]
    assert_equal "src/types/index.ts", error[:file]
    assert_equal 28, error[:line]
    assert_equal 5, error[:column]
    assert_equal :high, error[:severity]
    assert error[:auto_fixable]
  end

  # ========================
  # Context Extraction Tests
  # ========================

  test "extracts context from JSX tag mismatch errors" do
    log_content = <<~LOG
      ##[error]src/test.tsx(10,5): error TS17008: Unexpected closing 'span' tag does not match opening 'div' tag
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    error = errors.first
    
    assert_equal "div", error[:context][:opening_tag]
    assert_equal "span", error[:context][:closing_tag]
  end

  test "extracts context from property access errors" do
    log_content = <<~LOG
      ##[error]src/test.tsx(10,5): error TS2339: Property 'nonexistent' does not exist on type
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    error = errors.first
    
    assert_equal "nonexistent", error[:context][:property_name]
  end

  # ========================
  # Legacy Format Support Tests
  # ========================

  test "still detects legacy error formats" do
    log_content = <<~LOG
      Error: src/components/Old.tsx:25:10: Unexpected closing 'div' tag does not match opening 'section' tag
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :jsx_tag_mismatch, error[:type]
    assert_equal "src/components/Old.tsx", error[:file]
    assert_equal 25, error[:line]
    assert_equal 10, error[:column]
  end

  # ========================
  # TypeScript Error Detection Tests
  # ========================

  test "detects TypeScript property not found errors" do
    log_content = <<~LOG
      Error: src/components/Form.tsx:15:20: Property 'invalidProp' does not exist on type 'Props'
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :property_not_found, error[:type]
    assert_equal "src/components/Form.tsx", error[:file]
    assert_equal 15, error[:line]
    assert_equal 20, error[:column]
    assert_equal :medium, error[:severity]
  end

  test "detects undefined variable errors" do
    log_content = <<~LOG
      Error: src/utils/calc.ts:8:15: Cannot find name 'unknownVariable'
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :undefined_variable, error[:type]
    assert_equal "src/utils/calc.ts", error[:file]
    assert_equal 8, error[:line]
    assert_equal 15, error[:column]
    assert_equal :medium, error[:severity]
  end

  test "detects type mismatch errors" do
    log_content = <<~LOG
      Error: src/hooks/useApi.ts:22:10: Type 'string' is not assignable to type 'number'
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :type_mismatch, error[:type]
    assert_equal "src/hooks/useApi.ts", error[:file]
    assert_equal 22, error[:line]
    assert_equal 10, error[:column]
    assert_equal :medium, error[:severity]
  end

  # ========================
  # Import/Module Error Tests
  # ========================

  test "detects module not found errors" do
    log_content = <<~LOG
      Error: Cannot resolve module './nonexistent' from 'src/components/App.tsx'
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :module_not_found, error[:type]
    assert_equal "src/components/App.tsx", error[:file]
    assert_equal "./nonexistent", error[:module_name]
    assert_equal :high, error[:severity]
  end

  test "detects missing import errors" do
    log_content = <<~LOG
      Error: src/pages/Home.tsx: Cannot find module 'react-router' or its corresponding type declarations
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :missing_import, error[:type]
    assert_equal "src/pages/Home.tsx", error[:file]
    assert_equal "react-router", error[:module_name]
    assert_equal :medium, error[:severity]
  end

  # ========================
  # CSS Error Tests
  # ========================

  test "detects CSS syntax errors" do
    log_content = <<~LOG
      Error: src/styles/main.css:15:25: Expected '}' but found ';'
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :css_syntax_error, error[:type]
    assert_equal "src/styles/main.css", error[:file]
    assert_equal 15, error[:line]
    assert_equal 25, error[:column]
    assert_equal :low, error[:severity]
  end

  test "detects Tailwind CSS class errors" do
    log_content = <<~LOG
      warn - The utility `invalid-tailwind-class` is not available
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :invalid_tailwind_class, error[:type]
    assert_equal "invalid-tailwind-class", error[:class_name]
    assert_equal :low, error[:severity]
  end

  # ========================
  # Dependency Error Tests
  # ========================

  test "detects npm dependency resolution errors" do
    log_content = <<~LOG
      npm ERR! Cannot resolve dependency tree
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :dependency_resolution_error, error[:type]
    assert_equal :high, error[:severity]
  end

  test "detects npm dependency conflicts" do
    log_content = <<~LOG
      npm ERR! ERESOLVE unable to resolve dependency tree
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 1, errors.length
    error = errors.first
    
    assert_equal :dependency_conflict, error[:type]
    assert_equal :high, error[:severity]
  end

  # ========================
  # Path Extraction Tests
  # ========================

  test "extracts relative paths correctly" do
    log_content = <<~LOG
      ##[error]/github/workspace/src/components/Test.tsx(10,5): error TS2315: JSX element 'div' has no corresponding closing tag.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    error = errors.first
    
    assert_equal "src/components/Test.tsx", error[:file]
  end

  test "handles paths without workspace indicator" do
    log_content = <<~LOG
      ##[error]src/pages/About.tsx(20,8): error TS1005: ';' expected.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    error = errors.first
    
    assert_equal "src/pages/About.tsx", error[:file]
  end

  # ========================
  # Multiple Error Detection Tests
  # ========================

  test "detects multiple errors in single log" do
    log_content = <<~LOG
      ##[error]src/pages/Home.tsx(15,10): error TS2315: JSX element 'div' has no corresponding closing tag.
      ##[error]src/components/Button.tsx(8,25): error TS1002: Unterminated string literal.
      ##[error]src/utils/helpers.ts(42,5): error TS1005: ';' expected.
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 3, errors.length
    
    # Verify each error type
    assert_equal :jsx_unclosed_tag, errors[0][:type]
    assert_equal :unterminated_string, errors[1][:type]
    assert_equal :missing_semicolon, errors[2][:type]
  end

  test "handles mixed modern and legacy error formats" do
    log_content = <<~LOG
      ##[error]src/new/Component.tsx(10,5): error TS2315: JSX element 'section' has no corresponding closing tag.
      Error: src/old/Legacy.tsx:25:10: Unexpected closing 'div' tag does not match opening 'span' tag
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    
    assert_equal 2, errors.length
    assert_equal :jsx_unclosed_tag, errors[0][:type]
    assert_equal :jsx_tag_mismatch, errors[1][:type]
  end

  # ========================
  # Edge Cases and Error Handling
  # ========================

  test "handles empty log content gracefully" do
    errors = @detector.analyze_build_errors([{ logs: "" }])
    assert_equal 0, errors.length
  end

  test "handles logs with no errors" do
    log_content = <<~LOG
      Build started...
      Compiling TypeScript files...
      Build completed successfully!
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    assert_equal 0, errors.length
  end

  test "skips non-fixable error types" do
    log_content = <<~LOG
      ##[error]src/test.tsx(10,5): error TS9999: Some unknown error type that we don't handle
    LOG

    errors = @detector.analyze_build_errors([{ logs: log_content }])
    assert_equal 0, errors.length # Should skip unknown error types
  end

  # ========================
  # Auto-Fixable Detection Tests
  # ========================

  test "correctly identifies auto-fixable errors" do
    fixable_log = <<~LOG
      ##[error]src/test.tsx(10,5): error TS2315: JSX element 'div' has no corresponding closing tag.
      ##[error]src/test.tsx(15,8): error TS1005: ';' expected.
      ##[error]src/test.tsx(20,12): error TS1002: Unterminated string literal.
    LOG

    errors = @detector.analyze_build_errors([{ logs: fixable_log }])
    
    assert_equal 3, errors.length
    errors.each do |error|
      assert error[:auto_fixable], "Error #{error[:type]} should be auto-fixable"
    end
  end

  test "correctly identifies non-auto-fixable errors" do
    non_fixable_log = <<~LOG
      Error: src/test.tsx:10:5: Property 'complexProperty' does not exist on type 'ComplexInterface'
    LOG

    errors = @detector.analyze_build_errors([{ logs: non_fixable_log }])
    
    assert_equal 1, errors.length
    refute errors.first[:auto_fixable], "Property errors should not be auto-fixable"
  end
end