require "test_helper"

class Ai::CodeValidatorTest < ActiveSupport::TestCase
  # Test TypeScript validation
  test "should pass valid TypeScript function component with return statement" do
    content = <<~TS
      export default function OrderForm() {
        const [email, setEmail] = useState("");
        
        if (loading) {
          return <div>Loading...</div>;
        }
        
        return (
          <div>
            <h1>Order Form</h1>
            <input value={email} onChange={(e) => setEmail(e.target.value)} />
          </div>
        );
      }
    TS

    result = Ai::CodeValidator.validate_typescript(content, "OrderForm.tsx")
    assert result[:valid], "Should accept valid function component with return statement"
    assert_empty result[:errors] || []
  end

  test "should pass TypeScript function with nested blocks and return" do
    content = <<~TS
      export function ComplexComponent() {
        const [state, setState] = useState(false);
        
        for (let i = 0; i < 10; i++) {
          if (i === 5) {
            console.log("midpoint");
          }
        }
        
        return <div>Complex Component</div>;
      }
    TS

    result = Ai::CodeValidator.validate_typescript(content, "ComplexComponent.tsx")
    assert result[:valid], "Should accept function with nested blocks and return"
    assert_empty result[:errors] || []
  end

  test "should detect incorrect useState destructuring" do
    content = <<~TS
      export default function BadComponent() {
        const state = useState(false);
        return <div>Bad</div>;
      }
    TS

    result = Ai::CodeValidator.validate_typescript(content, "BadComponent.tsx")
    assert_not result[:valid], "Should detect incorrect useState syntax"
    assert_includes result[:errors], "Incorrect useState destructuring syntax"
  end

  test "should accept correct useState destructuring" do
    content = <<~TS
      export default function GoodComponent() {
        const [isOpen, setIsOpen] = useState(false);
        const [count, setCount] = useState(0);
        return <div>Good</div>;
      }
    TS

    result = Ai::CodeValidator.validate_typescript(content, "GoodComponent.tsx")
    assert result[:valid], "Should accept correct useState syntax"
    assert_empty result[:errors] || []
  end

  # Test JSX validation
  test "should pass valid JSX with balanced tags" do
    content = <<~JSX
      <div className="container">
        <header>
          <h1>Title</h1>
        </header>
        <main>
          <section>
            <p>Content</p>
          </section>
        </main>
      </div>
    JSX

    result = Ai::CodeValidator.validate_jsx_syntax(content, "Component.jsx")
    assert result[:valid], "Should accept valid JSX with balanced tags"
  end

  test "should detect mismatched JSX tags" do
    content = <<~JSX
      <div>
        <span>
        </div>
      </span>
    JSX

    result = Ai::CodeValidator.validate_jsx_syntax(content, "BadComponent.jsx")
    assert_not result[:valid], "Should detect mismatched tags"
    assert result[:errors].any? { |e| e.include?("Mismatched") }
  end

  test "should detect unclosed JSX tags" do
    content = <<~JSX
      <div>
        <span>
          Content
      </div>
    JSX

    result = Ai::CodeValidator.validate_jsx_syntax(content, "UnclosedComponent.jsx")
    assert_not result[:valid], "Should detect unclosed tags"
    assert result[:errors].any? { |e| e.include?("Unclosed") || e.include?("Mismatched") }
  end

  test "should accept self-closing JSX tags" do
    content = <<~JSX
      <div>
        <input type="text" />
        <br />
        <img src="test.png" alt="test" />
      </div>
    JSX

    result = Ai::CodeValidator.validate_jsx_syntax(content, "SelfClosing.jsx")
    assert result[:valid], "Should accept self-closing tags"
  end

  test "should detect class instead of className in JSX" do
    content = <<~JSX
      <div class="container">
        <p>Content</p>
      </div>
    JSX

    result = Ai::CodeValidator.validate_jsx_syntax(content, "ClassAttribute.jsx")
    assert_not result[:valid], "Should detect class instead of className"
    assert result[:errors].any? { |e| e.include?("className") }
  end

  test "should accept className in JSX" do
    content = <<~JSX
      <div className="container">
        <p className="text">Content</p>
      </div>
    JSX

    result = Ai::CodeValidator.validate_jsx_syntax(content, "ClassNameAttribute.jsx")
    assert result[:valid], "Should accept className attribute"
  end

  # Test CSS validation
  test "should fix missing closing brace in nested @layer blocks" do
    # This is the exact issue from the FunnelCraft build failure
    content = <<~CSS
      @layer base {
        * {
          @apply border-border;
        }
        
        body {
          @apply bg-background text-foreground;
      /* OverSkill Branding */
      @layer components {
        .overskill-badge {
          @apply fixed bottom-4 right-4;
        }
      }
    CSS

    fixed = Ai::CodeValidator.validate_and_fix_css(content)
    # Should add missing closing brace for body selector
    assert fixed.include?("body {"), "Should preserve body selector"
    assert fixed.match?(/body\s*\{[^}]*@apply[^}]*\}/m), "Should close body block properly"
    # Should properly close both @layer blocks
    assert_equal 2, fixed.scan(/@layer/).count, "Should have 2 @layer directives"
    assert_equal fixed.count("{"), fixed.count("}"), "Should have balanced braces"
  end

  test "should fix extra closing braces in CSS" do
    content = <<~CSS
      .container {
        padding: 20px;
      }}
      
      @keyframes slide {
        from { left: 0; }
        to { left: 100%; }
      }}
    CSS

    fixed = Ai::CodeValidator.validate_and_fix_css(content)
    assert_equal fixed.count("{"), fixed.count("}"), "Should have balanced braces"
    assert fixed.include?(".container {"), "Should preserve valid CSS"
  end

  test "should add missing semicolons in CSS" do
    content = <<~CSS
      .container {
        padding: 20px
        margin: 10px;
      }
    CSS

    fixed = Ai::CodeValidator.validate_and_fix_css(content)
    assert fixed.include?("padding: 20px;"), "Should add missing semicolon"
    assert fixed.include?("margin: 10px;"), "Should preserve existing semicolon"
  end

  test "should handle complex nested CSS correctly" do
    content = <<~CSS
      @media (min-width: 768px) {
        .container {
          padding: 20px;
          
          &:hover {
            background: blue;
          }
        }
      }
    CSS

    fixed = Ai::CodeValidator.validate_and_fix_css(content)
    assert fixed.include?("@media"), "Should preserve media query"
    assert fixed.include?(".container"), "Should preserve nested rules"
  end

  # Additional tests for the specific FunnelCraft issue
  test "should detect and fix unclosed body selector with nested @layer" do
    # This is the exact pattern that caused the FunnelCraft failure
    content = <<~CSS
      @layer base {
        body {
          @apply bg-background text-foreground;
      /* OverSkill Branding */
      @layer components {
        .overskill-badge {
          @apply fixed bottom-4 right-4;
        }
      }
    CSS

    # Should detect structural issues and fix them
    syntax_check = Ai::CodeValidator.fix_css_syntax_issues(content)

    if syntax_check[:fixed]
      fixed_content = syntax_check[:content]
      # Verify braces are balanced after fix
      opening_braces = fixed_content.count("{")
      closing_braces = fixed_content.count("}")
      assert_equal opening_braces, closing_braces, "Should balance braces after fixing"

      # Should have proper structure
      assert fixed_content.match?(/body\s*\{[^}]*\}/m), "Body selector should be properly closed"
      assert fixed_content.match?(/@layer\s+components\s*\{/), "Components layer should be preserved"
    else
      flunk "Should have detected CSS structure issues requiring fixes"
    end
  end

  test "should detect extra closing braces" do
    content = <<~CSS
      .container {
        padding: 20px;
      }
      }
      }
    CSS

    syntax_check = Ai::CodeValidator.fix_css_syntax_issues(content)
    assert syntax_check[:fixed], "Should detect extra closing braces"
    assert syntax_check[:fixes].any? { |f| f.include?("extra closing brace") }, "Should report extra brace fixes"

    fixed_content = syntax_check[:content]
    opening_braces = fixed_content.count("{")
    closing_braces = fixed_content.count("}")
    assert_equal opening_braces, closing_braces, "Should balance braces after removing extras"
  end

  test "should detect missing closing braces in nested structures" do
    content = <<~CSS
      @layer base {
        .selector-one {
          color: red;
        
        .selector-two {
          color: blue;
        }
      /* Missing closing brace for selector-one and @layer base */
    CSS

    syntax_check = Ai::CodeValidator.fix_css_syntax_issues(content)
    assert syntax_check[:fixed], "Should detect missing closing braces"

    fixed_content = syntax_check[:content]
    opening_braces = fixed_content.count("{")
    closing_braces = fixed_content.count("}")
    assert_equal opening_braces, closing_braces, "Should balance braces after adding missing ones"
  end

  test "should handle PostCSS @apply directives correctly" do
    content = <<~CSS
      .component {
        @apply bg-blue-500 text-white p-4;
      }
      
      .another {
        @apply flex items-center
      }
    CSS

    fixed = Ai::CodeValidator.validate_and_fix_css(content)
    # Should add semicolon after @apply without one
    assert fixed.include?("@apply flex items-center;"), "Should add missing semicolon after @apply"
    assert fixed.include?("@apply bg-blue-500 text-white p-4;"), "Should preserve existing semicolons"
  end

  test "should validate real-world Tailwind CSS structure" do
    # This mirrors the actual structure from our apps
    content = <<~CSS
      @tailwind base;
      @tailwind components;
      @tailwind utilities;

      @layer base {
        :root {
          --background: 0 0% 100%;
        }
        
        body {
          @apply bg-background text-foreground;
        }
      }

      @layer components {
        .btn-primary {
          @apply bg-blue-500 text-white px-4 py-2 rounded;
        }
      }
    CSS

    # Should pass validation without changes
    fixed = Ai::CodeValidator.validate_and_fix_css(content)
    syntax_check = Ai::CodeValidator.fix_css_syntax_issues(fixed)
    assert_not syntax_check[:fixed], "Valid Tailwind structure should not need fixes"

    # Verify structure is preserved
    assert fixed.include?("@tailwind base"), "Should preserve Tailwind directives"
    assert fixed.include?("@layer base"), "Should preserve @layer blocks"
    assert fixed.include?("@layer components"), "Should preserve component layer"
  end

  # Integration test for validate_file
  test "should validate and process TypeScript files correctly" do
    content = <<~TS
      export default function TestComponent() {
        const [count, setCount] = useState(0);
        
        return (
          <div className="test">
            <p>Count: {count}</p>
          </div>
        );
      }
    TS

    result = Ai::CodeValidator.validate_file(content, "TestComponent.tsx")
    assert_equal content, result, "Should return content unchanged for valid TypeScript"
  end

  test "should validate and fix CSS files correctly" do
    content = <<~CSS
      .test {
        color: red
      }}
    CSS

    result = Ai::CodeValidator.validate_file(content, "styles.css")
    assert_not result.include?("}}"), "Should fix CSS issues"
    assert result.include?("color: red;"), "Should add missing semicolon"
  end
end
