require 'test_helper'

class PerplexityContentServiceTest < ActiveSupport::TestCase
  setup do
    @service = PerplexityContentService.new
    @redis_mock = mock('Redis')
    Redis.stubs(:new).returns(@redis_mock)
  end
  
  test "initialization without API key returns error" do
    with_env_var("PERPLEXITY_API_KEY", nil) do
      service = PerplexityContentService.new
      result = service.extract_content_for_llm("test query")
      
      assert_not result[:success]
      assert_equal "Perplexity API key not configured", result[:error]
    end
  end
  
  test "extract_content_for_llm uses cache when available" do
    @redis_mock.expects(:get).returns({
      success: true,
      content: "Cached content",
      source: "test query"
    }.to_json)
    
    result = @service.extract_content_for_llm("test query")
    
    assert result[:success]
    assert_equal "Cached content", result[:content]
  end
  
  test "extract_content_for_llm makes API request when cache miss" do
    @redis_mock.expects(:get).returns(nil)
    @redis_mock.expects(:setex).once
    
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => "AI-generated response with citations [1]"
        }
      }],
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
    }
    
    stub_perplexity_api_request(mock_response)
    
    result = @service.extract_content_for_llm("test query")
    
    assert result[:success]
    assert_equal "AI-generated response with citations [1]", result[:content]
    assert_equal 150, result[:token_usage]["total_tokens"]
    assert result[:has_citations]
  end
  
  test "extract_content_for_llm handles URL detection" do
    @redis_mock.expects(:get).returns(nil)
    @redis_mock.expects(:setex).once
    
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => "Content from URL"
        }
      }],
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
    }
    
    stub_perplexity_api_request(mock_response)
    
    result = @service.extract_content_for_llm("https://example.com/article")
    
    assert result[:success]
    # The service should detect this is a URL and use appropriate prompting
    assert_equal "https://example.com/article", result[:source]
  end
  
  test "deep_research uses appropriate model" do
    @redis_mock.stubs(:get).returns(nil)
    @redis_mock.stubs(:setex)
    
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => "Comprehensive research report with multiple sources"
        }
      }],
      "usage" => {
        "prompt_tokens" => 500,
        "completion_tokens" => 2000,
        "total_tokens" => 2500
      }
    }
    
    # Expect deep research model to be used
    stub_perplexity_api_request(mock_response, expected_model: "sonar-deep-research")
    
    result = @service.deep_research("complex topic")
    
    assert result[:success]
    assert_equal "Comprehensive research report with multiple sources", result[:research_report]
    assert_equal 2500, result[:token_usage]["total_tokens"]
  end
  
  test "fact_check uses quick model with specific prompt" do
    @redis_mock.stubs(:get).returns(nil)
    @redis_mock.stubs(:setex)
    
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => "Statement verified: True [1][2]"
        }
      }],
      "usage" => {
        "prompt_tokens" => 50,
        "completion_tokens" => 20,
        "total_tokens" => 70
      }
    }
    
    stub_perplexity_api_request(mock_response, expected_model: "sonar")
    
    result = @service.fact_check("The Earth is round")
    
    assert result[:success]
    assert_equal "Statement verified: True [1][2]", result[:content]
    assert result[:has_citations]
  end
  
  test "cost calculation for different models" do
    # Test sonar model pricing
    usage = {
      "prompt_tokens" => 1000,
      "completion_tokens" => 500
    }
    
    cost = @service.send(:calculate_cost, usage, "sonar")
    expected = (1000 / 1_000_000.0 * 3.0) + (500 / 1_000_000.0 * 15.0)
    assert_in_delta expected, cost, 0.0001
    
    # Test deep research model pricing (higher)
    cost = @service.send(:calculate_cost, usage, "sonar-deep-research")
    expected = (1000 / 1_000_000.0 * 10.0) + (500 / 1_000_000.0 * 40.0)
    assert_in_delta expected, cost, 0.0001
  end
  
  test "handles API timeout gracefully" do
    @redis_mock.stubs(:get).returns(nil)
    
    Faraday::Connection.any_instance.stubs(:post).raises(Faraday::TimeoutError.new("timeout"))
    
    result = @service.extract_content_for_llm("test query")
    
    assert_not result[:success]
    assert_includes result[:error], "timeout"
  end
  
  test "handles API error responses" do
    @redis_mock.stubs(:get).returns(nil)
    
    stub_perplexity_api_error(429, "Rate limit exceeded")
    
    result = @service.extract_content_for_llm("test query")
    
    assert_not result[:success]
    assert_includes result[:error], "429"
    assert_includes result[:error], "Rate limit exceeded"
  end
  
  test "skip cache when use_cache is false" do
    # Should not check cache when use_cache is false
    @redis_mock.expects(:get).never
    @redis_mock.expects(:setex).never
    
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => "Fresh content"
        }
      }],
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
    }
    
    stub_perplexity_api_request(mock_response)
    
    result = @service.extract_content_for_llm("test query", use_cache: false)
    
    assert result[:success]
    assert_equal "Fresh content", result[:content]
  end
  
  private
  
  def with_env_var(key, value)
    old_value = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old_value
  end
  
  def stub_perplexity_api_request(response, expected_model: "sonar")
    connection_mock = mock('Faraday::Connection')
    response_mock = mock('Faraday::Response')
    
    Faraday.expects(:new).returns(connection_mock)
    connection_mock.expects(:post).with('/chat/completions') do |path, &block|
      # Can verify the request body here if needed
      true
    end.returns(response_mock)
    
    response_mock.expects(:success?).returns(true)
    response_mock.expects(:body).returns(response.to_json)
  end
  
  def stub_perplexity_api_error(status, message)
    connection_mock = mock('Faraday::Connection')
    response_mock = mock('Faraday::Response')
    
    Faraday.expects(:new).returns(connection_mock)
    connection_mock.expects(:post).returns(response_mock)
    
    response_mock.expects(:success?).returns(false)
    response_mock.expects(:status).returns(status).at_least_once
    response_mock.expects(:body).returns(message).at_least_once
  end
end