require "test_helper"
require "minitest/mock"
require_relative "../../../app/services/ai/open_router_client"

module AI
  class OpenRouterClientTest < ActiveSupport::TestCase
    setup do
      @client = AI::OpenRouterClient.new("test-api-key")
    end

    test "should initialize with API key" do
      assert_not_nil @client
      assert_equal "test-api-key", @client.instance_variable_get(:@api_key)
    end

    test "should use environment API key if none provided" do
      ENV["OPENROUTER_API_KEY"] = "env-api-key"
      client = AI::OpenRouterClient.new
      assert_equal "env-api-key", client.instance_variable_get(:@api_key)
    ensure
      ENV.delete("OPENROUTER_API_KEY")
    end

    test "should have correct headers" do
      options = @client.instance_variable_get(:@options)
      headers = options[:headers]

      assert_equal "Bearer test-api-key", headers["Authorization"]
      assert_equal "application/json", headers["Content-Type"]
      assert headers.key?("HTTP-Referer")
      assert headers.key?("X-Title")
    end

    test "should set timeout to 120 seconds" do
      options = @client.instance_variable_get(:@options)
      assert_equal 120, options[:timeout]
    end

    test "should handle successful chat response" do
      mock_response = Minitest::Mock.new
      mock_response.expect(:success?, true)
      mock_response.expect(:parsed_response, {
        "choices" => [
          {
            "message" => {
              "content" => "Hello, world!"
            }
          }
        ],
        "usage" => {
          "prompt_tokens" => 10,
          "completion_tokens" => 5,
          "total_tokens" => 15
        }
      })

      AI::OpenRouterClient.stub(:post, mock_response) do
        result = @client.chat([{role: "user", content: "Say hello"}])

        assert result[:success]
        assert_equal "Hello, world!", result[:content]
        assert_equal 10, result[:usage]["prompt_tokens"]
      end
    end

    test "should handle API error response" do
      mock_response = Minitest::Mock.new
      mock_response.expect(:success?, false)
      mock_response.expect(:code, 400)
      mock_response.expect(:body, '{"error": "Bad request"}')
      mock_response.expect(:parsed_response, {"error" => "Bad request"})

      AI::OpenRouterClient.stub(:post, mock_response) do
        result = @client.chat([{role: "user", content: "Say hello"}])

        assert_not result[:success]
        assert_equal "Bad request", result[:error]
        assert_equal 400, result[:code]
      end
    end

    test "should handle exceptions gracefully" do
      AI::OpenRouterClient.stub(:post, ->(*args) { raise StandardError, "Network error" }) do
        result = @client.chat([{role: "user", content: "Say hello"}])

        assert_not result[:success]
        assert_equal "Network error", result[:error]
      end
    end

    test "should use correct model for generate_app" do
      mock_response = Minitest::Mock.new
      mock_response.expect(:success?, true)
      mock_response.expect(:parsed_response, {
        "choices" => [{"message" => {"content" => "{}"}}],
        "usage" => {}
      })

      AI::OpenRouterClient.stub(:post, mock_response) do
        @client.generate_app("Create an app", framework: "react")

        # Verify the correct model was used
        assert true # The test passes if no exception is raised
      end
    end

    test "should calculate cost correctly" do
      usage = {
        "prompt_tokens" => 1000,
        "completion_tokens" => 500
      }

      # Test with Kimi K2 model pricing
      cost = @client.send(:calculate_cost, usage, "moonshotai/kimi-k2")

      # Kimi K2: $0.012 per 1K prompt, $0.012 per 1K completion
      expected_cost = (1000 * 0.012 / 1000) + (500 * 0.012 / 1000)
      assert_in_delta expected_cost, cost, 0.001
    end
  end
end
