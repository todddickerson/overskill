require 'test_helper'

class Deployment::CloudflareWorkerOptimizerTest < ActiveSupport::TestCase
  setup do
    @app = apps(:one) 
    @optimizer = Deployment::CloudflareWorkerOptimizer.new(@app)
  end

  test "initializes with app and stats tracking" do
    assert_equal @app, @optimizer.instance_variable_get(:@app)
    assert_not_nil @optimizer.instance_variable_get(:@optimization_stats)
  end

  test "categorizes assets correctly" do
    assets = {
      'index.html' => 'x' * 10.kilobytes,        # critical_small
      'main.js' => 'x' * 30.kilobytes,           # critical_small
      'app.css' => 'x' * 40.kilobytes,           # critical_small
      'vendor.js' => 'x' * 200.kilobytes,        # non_critical
      'huge.css' => 'x' * 100.kilobytes,         # critical_large
      'image.png' => 'x' * 500.kilobytes         # non_critical
    }

    categories = @optimizer.send(:categorize_assets, assets)
    
    assert_includes categories[:critical_small].keys, 'index.html'
    assert_includes categories[:critical_small].keys, 'main.js'
    assert_includes categories[:critical_small].keys, 'app.css'
    assert_includes categories[:critical_large].keys, 'huge.css'
    assert_includes categories[:non_critical].keys, 'vendor.js'
    assert_includes categories[:non_critical].keys, 'image.png'
  end

  test "applies hybrid strategy moving large assets to R2" do
    assets = {
      'index.html' => 'x' * 10.kilobytes,
      'huge.js' => 'x' * 200.kilobytes
    }

    result = @optimizer.optimize_for_worker(assets: assets)
    
    assert result[:success]
    assert_includes result[:worker_assets].keys, 'index.html'
    assert_includes result[:r2_assets].keys, 'huge.js'
    assert result[:r2_assets]['huge.js'][:cdn_url].present?
  end

  test "validates worker size limit" do
    huge_assets = {
      'index.html' => 'x' * 500.kilobytes,
      'main.js' => 'x' * 600.kilobytes
    }

    assert_raises Deployment::CloudflareWorkerOptimizer::SizeViolationError do
      @optimizer.optimize_for_worker(assets: huge_assets)
    end
  end

  test "identifies critical assets correctly" do
    assert @optimizer.send(:critical_asset?, 'index.html')
    assert @optimizer.send(:critical_asset?, 'main.js')
    assert @optimizer.send(:critical_asset?, 'main.css')
    assert @optimizer.send(:critical_asset?, 'app.js')
    assert @optimizer.send(:critical_asset?, 'critical.css')
    assert @optimizer.send(:critical_asset?, 'font.woff2')
    
    assert_not @optimizer.send(:critical_asset?, 'vendor.js')
    assert_not @optimizer.send(:critical_asset?, 'chunk-123.js')
    assert_not @optimizer.send(:critical_asset?, 'image.png')
  end

  test "generates CDN URLs correctly" do
    path = '/assets/app.js'
    cdn_url = @optimizer.send(:generate_cdn_url, path)
    
    assert_equal "https://cdn.overskill.app/apps/#{@app.id}/assets/app.js", cdn_url
  end

  test "analyzes size requirements" do
    assets = {
      'index.html' => 'x' * 10.kilobytes,
      'main.js' => 'x' * 60.kilobytes,  # Oversized critical
      'vendor.js' => 'x' * 800.kilobytes
    }

    analysis = @optimizer.analyze_size_requirements(assets)
    
    assert_equal 870.kilobytes, analysis[:total_size]
    assert_equal 70.kilobytes, analysis[:critical_size]
    assert_equal 800.kilobytes, analysis[:non_critical_size]
    assert_not_empty analysis[:oversized_assets]
    assert analysis[:oversized_assets].any? { |a| a[:path] == 'main.js' }
    assert_includes analysis[:recommendations], 'Requires hybrid asset strategy (R2 offloading)'
  end

  test "monitors size compliance" do
    # Test healthy status
    small_script = 'x' * 500.kilobytes
    status = @optimizer.monitor_size_compliance(small_script)
    
    assert_equal 'healthy', status[:status]
    assert status[:utilization_percent] < 60
    assert_not status[:needs_optimization]
    
    # Test warning status
    medium_script = 'x' * 750.kilobytes
    status = @optimizer.monitor_size_compliance(medium_script)
    
    assert_equal 'warning', status[:status]
    assert status[:utilization_percent].between?(61, 80)
    assert_not status[:needs_optimization]
    
    # Test critical status
    large_script = 'x' * 920.kilobytes
    status = @optimizer.monitor_size_compliance(large_script)
    
    assert_equal 'critical', status[:status]
    assert status[:utilization_percent].between?(81, 95)
    assert status[:needs_optimization]
    
    # Test violation status
    huge_script = 'x' * 1.1.megabytes
    status = @optimizer.monitor_size_compliance(huge_script)
    
    assert_equal 'violation', status[:status]
    assert status[:utilization_percent] > 95
    assert status[:needs_optimization]
  end

  test "generates optimized worker script" do
    assets = {
      'index.html' => '<html>App</html>',
      'main.js' => 'console.log("app");'
    }

    result = @optimizer.optimize_for_worker(assets: assets)
    
    script = result[:worker_script]
    
    assert_includes script, "export default"
    assert_includes script, "App ##{@app.id}"
    assert_includes script, "CDN_ASSETS"
    assert_includes script, "async fetch(request, env, ctx)"
    assert_includes script, "handleApiRequest"
    assert_includes script, "serveSpaWithPreloads"
  end

  test "formats bytes correctly" do
    assert_equal "0 B", @optimizer.send(:format_bytes, 0)
    assert_equal "500 B", @optimizer.send(:format_bytes, 500)
    assert_equal "1.5 KB", @optimizer.send(:format_bytes, 1536)
    assert_equal "2.0 MB", @optimizer.send(:format_bytes, 2.megabytes)
    assert_equal "1.2 GB", @optimizer.send(:format_bytes, 1.2.gigabytes)
  end

  test "determines content types correctly" do
    assert_equal 'application/javascript', @optimizer.send(:determine_content_type, 'app.js')
    assert_equal 'text/css', @optimizer.send(:determine_content_type, 'styles.css')
    assert_equal 'text/html', @optimizer.send(:determine_content_type, 'index.html')
    assert_equal 'application/json', @optimizer.send(:determine_content_type, 'config.json')
    assert_equal 'font/woff2', @optimizer.send(:determine_content_type, 'font.woff2')
    assert_equal 'font/woff', @optimizer.send(:determine_content_type, 'font.woff')
  end

  test "generates optimization recommendations" do
    assets = {
      'index.html' => 'x' * 10.kilobytes,
      'huge.js' => 'x' * 800.kilobytes
    }

    result = @optimizer.optimize_for_worker(assets: assets)
    recommendations = result[:recommendations]
    
    assert recommendations.is_a?(Array)
    assert recommendations.any? { |r| r.include?('size reduction') }
  end

  test "tracks optimization statistics" do
    assets = {
      'index.html' => 'x' * 50.kilobytes,
      'vendor.js' => 'x' * 200.kilobytes
    }

    result = @optimizer.optimize_for_worker(assets: assets)
    stats = result[:optimization_stats]
    
    assert_equal 250.kilobytes, stats[:original_size]
    assert stats[:optimized_size] < stats[:original_size]
    assert_not_empty stats[:r2_assets]
    assert_not_empty stats[:worker_assets]
  end

  test "filters high priority assets for preloading" do
    categories = {
      critical_large: {
        'main.js' => 'x' * 100.kilobytes,
        'app.css' => 'x' * 80.kilobytes
      }
    }

    optimization_result = {
      worker_assets: {},
      r2_assets: {
        'main.js' => { cdn_url: 'https://cdn.overskill.app/main.js', priority: 'high' },
        'vendor.js' => { cdn_url: 'https://cdn.overskill.app/vendor.js', priority: 'normal' }
      }
    }

    high_priority = @optimizer.send(:filter_high_priority_assets, optimization_result[:r2_assets])
    
    assert_includes high_priority, 'https://cdn.overskill.app/main.js'
    assert_not_includes high_priority, 'https://cdn.overskill.app/vendor.js'
  end

  test "respects size limits and thresholds" do
    assert_equal 1.megabyte, Deployment::CloudflareWorkerOptimizer::WORKER_SIZE_LIMIT
    assert_equal 900.kilobytes, Deployment::CloudflareWorkerOptimizer::SAFE_WORKER_SIZE_LIMIT
    assert_equal 50.kilobytes, Deployment::CloudflareWorkerOptimizer::CRITICAL_ASSET_MAX_SIZE
    assert_equal 0.7, Deployment::CloudflareWorkerOptimizer::COMPRESSION_RATIO
  end
end