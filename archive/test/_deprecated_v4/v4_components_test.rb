#!/usr/bin/env ruby
# Standalone test to verify V4 components work in isolation

require "minitest/autorun"
require "active_support/all"
require "ostruct"
require "pathname"
require "logger"

# Minimal Rails-like environment setup
module Rails
  def self.root
    Pathname.new(File.expand_path("../", __dir__))
  end

  def self.logger
    @logger ||= Logger.new($stdout)
  end

  def self.application
    Struct.new(:credentials, :routes).new(
      OpenStruct.new(cloudflare: {
        account_id: "test",
        zone_id: "test",
        api_token: "test",
        email: "test@example.com",
        r2_bucket: "test"
      }),
      OpenStruct.new(url_helpers: Module.new)
    )
  end

  def self.cache
    @cache ||= ActiveSupport::Cache::MemoryStore.new
  end

  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

# Load V4 services
require_relative "../app/services/deployment/cloudflare_worker_optimizer"
require_relative "../app/services/deployment/vite_builder_service"

class V4ComponentsTest < Minitest::Test
  def setup
    @app = OpenStruct.new(
      id: 123,
      name: "Test App",
      app_files: [],
      latest_version: OpenStruct.new(id: 1)
    )
  end

  def test_cloudflare_worker_optimizer_initializes
    optimizer = Deployment::CloudflareWorkerOptimizer.new(@app)
    assert_equal @app, optimizer.instance_variable_get(:@app)
  end

  def test_cloudflare_worker_optimizer_categorizes_assets
    optimizer = Deployment::CloudflareWorkerOptimizer.new(@app)

    assets = {
      "index.html" => "x" * 10.kilobytes,  # critical_small
      "vendor.js" => "x" * 200.kilobytes,   # non_critical
      "huge.css" => "x" * 100.kilobytes     # critical_large
    }

    categories = optimizer.send(:categorize_assets, assets)

    assert categories[:critical_small].key?("index.html")
    assert categories[:non_critical].key?("vendor.js")
    assert categories[:critical_large].key?("huge.css")
  end

  def test_vite_builder_service_initializes
    service = Deployment::ViteBuilderService.new(@app)
    assert_equal @app, service.instance_variable_get(:@app)
  end

  def test_vite_builder_determines_build_mode
    service = Deployment::ViteBuilderService.new(@app)

    assert_equal :production, service.determine_build_mode("deploy to production")
    assert_equal :production, service.determine_build_mode("publish my app")
    assert_equal :development, service.determine_build_mode("preview the app")
    assert_equal :development, service.determine_build_mode("build a todo app")
    assert_equal :development, service.determine_build_mode(nil)
  end

  def test_worker_size_limits_are_correct
    assert_equal 1.megabyte, Deployment::CloudflareWorkerOptimizer::WORKER_SIZE_LIMIT
    assert_equal 900.kilobytes, Deployment::CloudflareWorkerOptimizer::SAFE_WORKER_SIZE_LIMIT
    assert_equal 900.kilobytes, Deployment::ViteBuilderService::MAX_WORKER_SIZE
  end

  def test_optimizer_generates_cdn_urls
    optimizer = Deployment::CloudflareWorkerOptimizer.new(@app)
    path = "assets/app.js"
    cdn_url = optimizer.send(:generate_cdn_url, path)

    assert_equal "https://cdn.overskill.app/apps/123/assets/app.js", cdn_url
  end

  def test_optimizer_analyzes_size_requirements
    optimizer = Deployment::CloudflareWorkerOptimizer.new(@app)

    assets = {
      "index.html" => "x" * 10.kilobytes,
      "main.js" => "x" * 60.kilobytes,  # Oversized critical
      "vendor.js" => "x" * 800.kilobytes
    }

    analysis = optimizer.analyze_size_requirements(assets)

    assert_equal 870.kilobytes, analysis[:total_size]
    assert_equal 70.kilobytes, analysis[:critical_size]
    assert_equal 800.kilobytes, analysis[:non_critical_size]
    assert analysis[:oversized_assets].any? { |a| a[:path] == "main.js" }
    assert_includes analysis[:recommendations], "Requires hybrid asset strategy (R2 offloading)"
  end

  def test_optimizer_validates_worker_size
    optimizer = Deployment::CloudflareWorkerOptimizer.new(@app)

    # Should pass with small assets
    small_assets = {
      "index.html" => "x" * 10.kilobytes,
      "main.js" => "x" * 30.kilobytes
    }

    result = optimizer.optimize_for_worker(assets: small_assets)
    assert result[:success]

    # Should fail with huge critical assets
    huge_assets = {
      "index.html" => "x" * 500.kilobytes,
      "main.js" => "x" * 600.kilobytes
    }

    assert_raises Deployment::CloudflareWorkerOptimizer::SizeViolationError do
      optimizer.optimize_for_worker(assets: huge_assets)
    end
  end

  def test_complete_optimization_flow
    optimizer = Deployment::CloudflareWorkerOptimizer.new(@app)

    # Mixed asset sizes to test hybrid strategy
    assets = {
      "index.html" => "<html>Test App</html>",          # Small critical - keep in worker
      "main.js" => 'console.log("app");' * 100,        # Small critical - keep in worker
      "vendor.js" => "x" * 200.kilobytes,              # Large non-critical - move to R2
      "styles.css" => "body { margin: 0; }" * 5000     # Large critical - move to R2
    }

    result = optimizer.optimize_for_worker(assets: assets)

    assert result[:success]
    assert result[:worker_script].include?("export default")
    assert result[:worker_assets].key?("index.html")
    assert result[:worker_assets].key?("main.js")
    assert result[:r2_assets].key?("vendor.js")
    assert result[:r2_assets]["vendor.js"][:cdn_url].present?
    assert result[:optimization_stats][:original_size] > 0
    assert result[:recommendations].is_a?(Array)
  end
end

# Run the tests
if __FILE__ == $0
  puts "Running V4 Components Tests..."
  puts "=" * 60
  exit Minitest.run(ARGV)
end
