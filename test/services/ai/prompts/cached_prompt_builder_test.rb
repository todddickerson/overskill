require "test_helper"

module Ai
  module Prompts
    class CachedPromptBuilderTest < ActiveSupport::TestCase
      setup do
        @base_prompt = "You are an AI assistant for building web applications."

        # Mock template files
        @template_files = [
          OpenStruct.new(path: "src/App.tsx", content: "x" * 5000),  # 5K chars
          OpenStruct.new(path: "src/main.tsx", content: "y" * 3000), # 3K chars
          OpenStruct.new(path: "package.json", content: '{"name": "test"}')
        ]

        @context_data = {
          iteration_data: {
            iteration: 3,
            max_iterations: 10,
            files_generated: 5,
            last_action: "execute_tools",
            confidence: 75
          }
        }

        @builder = CachedPromptBuilder.new(
          base_prompt: @base_prompt,
          template_files: @template_files,
          context_data: @context_data
        )
      end

      test "builds system prompt array with cache_control for long content" do
        result = @builder.build_system_prompt_array

        assert_instance_of Array, result
        assert result.length >= 2, "Should have at least template and base prompt blocks"

        # First block should be template files with cache_control
        template_block = result.first
        assert_equal "text", template_block[:type]
        assert template_block[:text].include?("<documents>")
        assert_equal({type: "ephemeral"}, template_block[:cache_control])

        # Second block should be base prompt with cache_control
        base_block = result[1]
        assert_equal "text", base_block[:type]
        assert_equal @base_prompt, base_block[:text]
        assert_equal({type: "ephemeral"}, base_block[:cache_control])

        # Last block should be dynamic context WITHOUT cache_control
        context_block = result.last
        assert_equal "text", context_block[:type]
        assert context_block[:text].include?("useful-context")
        assert_nil context_block[:cache_control], "Dynamic context should not be cached"
      end

      test "builds system prompt string with correct order" do
        result = @builder.build_system_prompt_string

        # Verify order: template files first, then base prompt, then context
        template_position = result.index("<documents>")
        base_position = result.index(@base_prompt)
        context_position = result.index("<useful-context>")

        assert template_position < base_position, "Template files should come before base prompt"
        assert base_position < context_position, "Base prompt should come before dynamic context"
      end

      test "formats template files with XML structure per docs" do
        result = @builder.build_system_prompt_string

        # Check for proper XML document structure
        assert result.include?('<document index="1">')
        assert result.include?("<source>src/App.tsx</source>")
        assert result.include?("<document_content>")
        assert result.include?("```typescript")
      end

      test "only caches substantial content" do
        # Builder with small content
        small_builder = CachedPromptBuilder.new(
          base_prompt: @base_prompt,
          template_files: [
            OpenStruct.new(path: "small.txt", content: "small")
          ],
          context_data: {}
        )

        result = small_builder.build_system_prompt_array

        # Small content should not have cache_control
        template_block = result.first
        if template_block[:text].length < 5000
          assert_nil template_block[:cache_control], "Small content should not be cached"
        end
      end

      test "estimates cache savings correctly" do
        savings = @builder.estimate_cache_savings

        assert savings[:template_files_tokens] > 0
        assert savings[:base_prompt_tokens] > 0
        assert_equal 0.83, savings[:estimated_cost_reduction]

        # Total cacheable should be sum of template and base
        expected_total = savings[:template_files_tokens] + savings[:base_prompt_tokens]
        assert_equal expected_total, savings[:total_cacheable_tokens]
      end

      test "formats iteration data correctly in context" do
        result = @builder.build_system_prompt_string

        assert result.include?("Iteration 3 of 10")
        assert result.include?("Files generated: 5")
        assert result.include?("Last action: execute_tools")
        assert result.include?("Confidence: 75%")
      end

      test "handles empty template files gracefully" do
        builder = CachedPromptBuilder.new(
          base_prompt: @base_prompt,
          template_files: [],
          context_data: @context_data
        )

        result = builder.build_system_prompt_array

        # Should not have template block
        refute result.any? { |block| block[:text].include?("<documents>") }

        # Should still have base prompt
        assert result.any? { |block| block[:text] == @base_prompt }
      end

      test "handles empty context data gracefully" do
        builder = CachedPromptBuilder.new(
          base_prompt: @base_prompt,
          template_files: @template_files,
          context_data: {}
        )

        result = builder.build_system_prompt_array

        # Should not have context block
        refute result.any? { |block| block[:text].include?("<useful-context>") }
      end

      test "detects language correctly for syntax highlighting" do
        files = [
          OpenStruct.new(path: "app.tsx", content: "const App = () => {}"),
          OpenStruct.new(path: "style.css", content: "body { margin: 0; }"),
          OpenStruct.new(path: "config.json", content: "{}"),
          OpenStruct.new(path: "script.rb", content: 'puts "hello"')
        ]

        builder = CachedPromptBuilder.new(
          base_prompt: @base_prompt,
          template_files: files,
          context_data: {}
        )

        result = builder.build_system_prompt_string

        assert result.include?("```typescript")
        assert result.include?("```css")
        assert result.include?("```json")
        assert result.include?("```ruby")
      end

      test "array format supports up to 4 cache breakpoints" do
        # Per Anthropic docs, we can have up to 4 cache breakpoints
        large_files = (1..10).map do |i|
          OpenStruct.new(path: "file#{i}.txt", content: "x" * 10000)
        end

        builder = CachedPromptBuilder.new(
          base_prompt: @base_prompt,
          template_files: large_files,
          context_data: @context_data
        )

        result = builder.build_system_prompt_array

        # Count blocks with cache_control
        cached_blocks = result.count { |block| block[:cache_control].present? }

        # Should have at most 4 cache breakpoints per Anthropic docs
        assert cached_blocks <= 4, "Should have at most 4 cache breakpoints"
      end
    end
  end
end
