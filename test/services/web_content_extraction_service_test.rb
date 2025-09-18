require "test_helper"

class WebContentExtractionServiceTest < ActiveSupport::TestCase
  setup do
    @service = WebContentExtractionService.new
    @redis_mock = mock("Redis")
    Redis.stubs(:new).returns(@redis_mock)
  end

  test "extract_for_llm validates URL format" do
    result = @service.extract_for_llm("not-a-url")

    assert_not result[:success]
    assert_equal false, result[:success]
    assert_includes result[:error], "Invalid URL"
  end

  test "extract_for_llm blocks local URLs for security" do
    dangerous_urls = [
      "http://localhost/admin",
      "http://127.0.0.1/secret",
      "http://192.168.1.1/router",
      "http://10.0.0.1/internal",
      "file:///etc/passwd"
    ]

    dangerous_urls.each do |url|
      result = @service.extract_for_llm(url)

      assert_not result[:success], "Should block #{url}"
      assert_includes result[:error], "blocked"
    end
  end

  test "extract_for_llm uses cache when available" do
    @redis_mock.expects(:get).returns({
      success: true,
      content: "Cached article content",
      url: "https://example.com",
      word_count: 3,
      char_count: 21
    }.to_json)

    result = @service.extract_for_llm("https://example.com")

    assert result[:success]
    assert_equal "Cached article content", result[:content]
    assert_equal 3, result[:word_count]
  end

  test "extract_for_llm fetches and processes HTML content" do
    @redis_mock.expects(:get).returns(nil)
    @redis_mock.expects(:setex).once

    html_content = <<-HTML
      <html>
        <head><title>Test Article</title></head>
        <body>
          <nav>Navigation menu</nav>
          <article>
            <h1>Main Article Title</h1>
            <p>This is the main content of the article that we want to extract.</p>
            <p>It contains multiple paragraphs with useful information.</p>
          </article>
          <aside>Sidebar content</aside>
          <footer>Footer links</footer>
        </body>
      </html>
    HTML

    stub_http_request("https://example.com/article", html_content)

    result = @service.extract_for_llm("https://example.com/article")

    assert result[:success]
    assert_includes result[:content], "Main Article Title"
    assert_includes result[:content], "main content of the article"
    assert_not_includes result[:content], "Navigation menu"
    assert_not_includes result[:content], "Footer links"
    assert result[:word_count] > 0
    assert result[:char_count] > 0
  end

  test "extract_for_llm handles timeout gracefully" do
    @redis_mock.expects(:get).returns(nil)

    Faraday::Connection.any_instance.stubs(:get).raises(Faraday::TimeoutError.new("timeout"))

    result = @service.extract_for_llm("https://example.com")

    assert_not result[:success]
    assert_includes result[:error], "timeout"
  end

  test "extract_for_llm handles HTTP errors" do
    @redis_mock.expects(:get).returns(nil)

    stub_http_error("https://example.com", 404)

    result = @service.extract_for_llm("https://example.com")

    assert_not result[:success]
    assert_includes result[:error], "404"
  end

  test "extract_for_llm truncates very long content" do
    @redis_mock.expects(:get).returns(nil)
    @redis_mock.expects(:setex).once

    # Create content longer than MAX_CONTENT_LENGTH
    long_content = "x" * 150_000
    html = "<html><body><article>#{long_content}</article></body></html>"

    stub_http_request("https://example.com", html)

    result = @service.extract_for_llm("https://example.com")

    assert result[:success]
    assert result[:truncated]
    assert result[:char_count] <= 100_000
  end

  test "extract_for_llm sanitizes sensitive data" do
    @redis_mock.expects(:get).returns(nil)
    @redis_mock.expects(:setex).once

    html_with_secrets = <<-HTML
      <html>
        <body>
          <article>
            <p>API Key: sk-1234567890abcdef</p>
            <p>Database password: super_secret_123</p>
            <p>Normal content here</p>
          </article>
        </body>
      </html>
    HTML

    stub_http_request("https://example.com", html_with_secrets)

    result = @service.extract_for_llm("https://example.com")

    assert result[:success]
    assert_includes result[:content], "Normal content"
    assert_includes result[:content], "[REDACTED]"
    assert_not_includes result[:content], "sk-1234567890abcdef"
    assert_not_includes result[:content], "super_secret_123"
  end

  test "extract_for_llm handles malformed HTML" do
    @redis_mock.expects(:get).returns(nil)
    @redis_mock.expects(:setex).once

    malformed_html = "<html><body><p>Unclosed paragraph <div>Nested content</body>"

    stub_http_request("https://example.com", malformed_html)

    result = @service.extract_for_llm("https://example.com")

    assert result[:success]
    assert_includes result[:content], "Unclosed paragraph"
    assert_includes result[:content], "Nested content"
  end

  test "skip cache when use_cache is false" do
    @redis_mock.expects(:get).never
    @redis_mock.expects(:setex).never

    html = "<html><body><p>Fresh content</p></body></html>"
    stub_http_request("https://example.com", html)

    result = @service.extract_for_llm("https://example.com", use_cache: false)

    assert result[:success]
    assert_includes result[:content], "Fresh content"
  end

  test "handles redirect responses" do
    @redis_mock.expects(:get).returns(nil)

    connection_mock = mock("Faraday::Connection")
    response_mock = mock("Faraday::Response")

    Faraday.expects(:new).returns(connection_mock)
    connection_mock.expects(:get).returns(response_mock)

    response_mock.expects(:status).returns(301).at_least_once
    response_mock.expects(:headers).returns({"Location" => "https://example.com/new"})

    result = @service.extract_for_llm("https://example.com/old")

    assert_not result[:success]
    assert_includes result[:error], "redirect"
  end

  test "respects response size limits" do
    @redis_mock.expects(:get).returns(nil)

    # Create response larger than MAX_RESPONSE_SIZE
    huge_html = "<html><body>" + ("x" * 6_000_000) + "</body></html>"

    connection_mock = mock("Faraday::Connection")
    response_mock = mock("Faraday::Response")

    Faraday.expects(:new).returns(connection_mock)
    connection_mock.expects(:get).returns(response_mock)

    response_mock.expects(:success?).returns(true)
    response_mock.expects(:body).returns(huge_html)
    response_mock.expects(:headers).returns({"content-type" => "text/html"})

    result = @service.extract_for_llm("https://example.com")

    assert_not result[:success]
    assert_includes result[:error], "too large"
  end

  private

  def stub_http_request(url, content, status: 200)
    connection_mock = mock("Faraday::Connection")
    response_mock = mock("Faraday::Response")

    Faraday.expects(:new).returns(connection_mock)
    connection_mock.expects(:get).returns(response_mock)

    response_mock.expects(:success?).returns(status == 200)
    response_mock.expects(:status).returns(status).at_least(0)
    response_mock.expects(:body).returns(content)
    response_mock.expects(:headers).returns({"content-type" => "text/html"})
  end

  def stub_http_error(url, status)
    connection_mock = mock("Faraday::Connection")
    response_mock = mock("Faraday::Response")

    Faraday.expects(:new).returns(connection_mock)
    connection_mock.expects(:get).returns(response_mock)

    response_mock.expects(:success?).returns(false)
    response_mock.expects(:status).returns(status).at_least_once
    response_mock.expects(:body).returns("Error #{status}")
  end
end
