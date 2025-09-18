require "test_helper"

class Deployment::ViteBuilderServiceTest < ActiveSupport::TestCase
  setup do
    @app = apps(:one)
    @app_version = app_versions(:one)
    @service = Deployment::ViteBuilderService.new(@app)

    # Stub latest_version
    @app.stub :latest_version, @app_version do
      @service = Deployment::ViteBuilderService.new(@app)
    end
  end

  test "initializes with app and version" do
    assert_equal @app, @service.instance_variable_get(:@app)
    assert_not_nil @service.instance_variable_get(:@app_version)
  end

  test "determines build mode based on user intent" do
    # Production keywords
    assert_equal :production, @service.determine_build_mode("deploy to production")
    assert_equal :production, @service.determine_build_mode("publish my app")
    assert_equal :production, @service.determine_build_mode("go live")

    # Development keywords
    assert_equal :development, @service.determine_build_mode("preview the app")
    assert_equal :development, @service.determine_build_mode("test staging")

    # Default to development for speed
    assert_equal :development, @service.determine_build_mode("build a todo app")
    assert_equal :development, @service.determine_build_mode(nil)
  end

  test "build_for_development returns expected structure" do
    # Mock the builder
    mock_result = {
      success: true,
      mode: :development,
      build_time: 42.5,
      worker_script: "export default { fetch() {} }",
      worker_size: 450_000,
      preview_url: "https://preview-#{@app.id}.overskill.app"
    }

    Deployment::FastDevelopmentBuilder.any_instance.stub :execute!, mock_result do
      result = @service.build_for_development!

      assert result[:success]
      assert_equal :development, result[:mode]
      assert_equal 42.5, result[:build_time]
      assert result[:worker_size] < Deployment::ViteBuilderService::MAX_WORKER_SIZE
      assert_includes result[:preview_url], @app.id.to_s
    end
  end

  test "build_for_production returns expected structure" do
    mock_result = {
      success: true,
      mode: :production,
      build_time: 175.2,
      worker_script: "export default { fetch() {} }",
      worker_size: 850_000,
      r2_assets: {"app.js" => {size: 200_000}},
      production_url: "https://app-#{@app.id}.overskill.app"
    }

    Deployment::ProductionOptimizedBuilder.any_instance.stub :execute!, mock_result do
      result = @service.build_for_production!

      assert result[:success]
      assert_equal :production, result[:mode]
      assert_equal 175.2, result[:build_time]
      assert_not_empty result[:r2_assets]
      assert_includes result[:production_url], @app.id.to_s
    end
  end

  test "raises BuildError when development build fails" do
    Deployment::FastDevelopmentBuilder.any_instance.stub :execute!, -> { raise StandardError, "Build failed" } do
      assert_raises Deployment::ViteBuilderService::BuildError do
        @service.build_for_development!
      end
    end
  end

  test "raises BuildError when production build fails" do
    Deployment::ProductionOptimizedBuilder.any_instance.stub :execute!, -> { raise StandardError, "Build failed" } do
      assert_raises Deployment::ViteBuilderService::BuildError do
        @service.build_for_production!
      end
    end
  end

  test "validates worker size limits" do
    assert 1.megabyte > Deployment::ViteBuilderService::MAX_WORKER_SIZE
    assert 900.kilobytes == Deployment::ViteBuilderService::MAX_WORKER_SIZE
  end

  test "build timeout constants are reasonable" do
    assert 60.seconds == Deployment::ViteBuilderService::FAST_BUILD_TIMEOUT
    assert 200.seconds == Deployment::ViteBuilderService::PRODUCTION_BUILD_TIMEOUT
  end
end

class Deployment::FastDevelopmentBuilderTest < ActiveSupport::TestCase
  setup do
    @app = apps(:one)
    @app_version = app_versions(:one)
    @builder = Deployment::FastDevelopmentBuilder.new(@app, @app_version)
  end

  test "generates development worker script" do
    assets = {"index.html" => "<html></html>", "main.js" => 'console.log("app")'}

    script = @builder.send(:generate_worker_script, assets, false)

    assert_includes script, "export default"
    assert_includes script, "Build mode: development"
    assert_includes script, "App ID: #{@app.id}"
    assert_includes script, "async fetch(request, env, ctx)"
  end

  test "prepare_source_files combines templates and app files" do
    # Mock SharedTemplateService
    template_files = {
      "package.json" => {content: '{"name": "app"}', type: "json"}
    }

    # Mock app files
    app_file = AppFile.new(path: "src/App.tsx", content: "export default App")
    @app.stub :app_files, [app_file] do
      Ai::SharedTemplateService.any_instance.stub :generate_all_templates, template_files do
        source_files = @builder.send(:prepare_source_files)

        assert_includes source_files.keys, "package.json"
        assert_includes source_files.keys, "src/App.tsx"
      end
    end
  end

  test "generates correct MIME types" do
    builder = Deployment::FastDevelopmentBuilder.new(@app, @app_version)

    assert_equal "application/javascript", builder.send(:mime_type_for, "app.js")
    assert_equal "text/css", builder.send(:mime_type_for, "styles.css")
    assert_equal "text/html", builder.send(:mime_type_for, "index.html")
    assert_equal "application/json", builder.send(:mime_type_for, "config.json")
  end

  test "detects file types correctly" do
    builder = Deployment::FastDevelopmentBuilder.new(@app, @app_version)

    assert_equal "typescript", builder.send(:detect_file_type, "app.tsx")
    assert_equal "typescript", builder.send(:detect_file_type, "types.ts")
    assert_equal "javascript", builder.send(:detect_file_type, "script.js")
    assert_equal "stylesheet", builder.send(:detect_file_type, "styles.css")
    assert_equal "html", builder.send(:detect_file_type, "index.html")
  end

  test "processes HTML templates with app variables" do
    content = "Welcome to {{APP_NAME}} (ID: {{APP_ID}}) in {{ENVIRONMENT}}"

    processed = @builder.send(:process_html_template, content)

    assert_includes processed, @app.name
    assert_includes processed, @app.id.to_s
    assert_includes processed, "development"
    assert_not_includes processed, "{{APP_NAME}}"
  end

  test "generates preview URL correctly" do
    url = @builder.send(:generate_preview_url)

    assert_equal "https://preview-#{@app.id}.overskill.app", url
  end

  test "executes within time limit" do
    Time.current

    # Mock fast execution
    @builder.stub :execute_vite_build, {success: true, assets: {}, bundle_size: 100} do
      @builder.stub :package_for_worker, {script: "worker", size: 100} do
        result = @builder.execute!

        # Should complete quickly (mocked)
        assert result[:build_time] < 60
      end
    end
  end
end

class Deployment::ProductionOptimizedBuilderTest < ActiveSupport::TestCase
  setup do
    @app = apps(:one)
    @app_version = app_versions(:one)
    @builder = Deployment::ProductionOptimizedBuilder.new(@app, @app_version)
  end

  test "optimizes source content for production" do
    content = <<~JS
      console.log("debug");
      /* block comment */
      // line comment
      function app() {
        return true;
      }
    JS

    optimized = @builder.send(:optimize_source_content, content)

    assert_not_includes optimized, "console.log"
    assert_not_includes optimized, "/* block comment */"
    assert_not_includes optimized, "// line comment"
    assert_includes optimized, "function app()"
  end

  test "determines critical assets correctly" do
    assert @builder.send(:critical_asset?, "index.html")
    assert @builder.send(:critical_asset?, "main.js")
    assert @builder.send(:critical_asset?, "main.css")
    assert @builder.send(:critical_asset?, "critical.js")

    assert_not @builder.send(:critical_asset?, "vendor.js")
    assert_not @builder.send(:critical_asset?, "chunk-123.js")
    assert_not @builder.send(:critical_asset?, "image.png")
  end

  test "generates production URL correctly" do
    url = @builder.send(:generate_production_url)

    assert_equal "https://app-#{@app.id}.overskill.app", url
  end

  test "uses CloudflareWorkerOptimizer for production builds" do
    mock_optimization = {
      worker_script: "optimized script",
      worker_size: 800_000,
      r2_assets: {"app.js" => {cdn_url: "https://cdn.overskill.app/app.js"}},
      optimization_stats: {original_size: 1_200_000, optimized_size: 800_000}
    }

    Deployment::CloudflareWorkerOptimizer.any_instance.stub :optimize_for_worker, mock_optimization do
      build_result = {assets: {"app.js" => "content"}}

      package = @builder.send(:package_for_production_worker, build_result)

      assert_equal "optimized script", package[:script]
      assert_equal 800_000, package[:size]
      assert_not_empty package[:r2_assets]
    end
  end

  test "handles worker size violations" do
    # Mock optimizer to raise size violation
    Deployment::CloudflareWorkerOptimizer.any_instance.stub :optimize_for_worker, ->(_) {
      raise Deployment::CloudflareWorkerOptimizer::SizeViolationError, "Too large"
    } do
      build_result = {assets: {"huge.js" => "x" * 2.megabytes}}

      assert_raises Deployment::ViteBuilderService::WorkerSizeExceededError do
        @builder.send(:package_for_production_worker, build_result)
      end
    end
  end
end
