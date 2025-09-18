require "test_helper"

class Deployment::CloudflareWorkersDeployerTest < ActiveSupport::TestCase
  setup do
    @team = Team.create!(name: "Test Team")
    @user = User.create!(email: "test@example.com", password: "password123")
    @membership = @team.memberships.create!(user: @user, role_ids: ["admin"])
    @app = App.create!(
      name: "Test App",
      team: @team,
      creator: @membership,
      prompt: "Test prompt"
    )
    @deployer = Deployment::CloudflareWorkersDeployer.new(@app)

    # Mock credentials
    Rails.application.credentials.stub :dig, "test_value" do
      @deployer = Deployment::CloudflareWorkersDeployer.new(@app)
    end
  end

  test "initializes with app and credentials" do
    assert_equal @app, @deployer.instance_variable_get(:@app)
    assert @deployer.instance_variable_get(:@account_id)
    assert @deployer.instance_variable_get(:@api_token)
  end

  test "generates correct worker names for deployment types" do
    preview_name = @deployer.send(:generate_worker_name, :preview)
    assert_equal "preview-app-#{@app.id}", preview_name

    production_name = @deployer.send(:generate_worker_name, :production)
    assert_equal "app-#{@app.id}", production_name

    custom_name = @deployer.send(:generate_worker_name, :staging)
    assert_equal "app-#{@app.id}-staging", custom_name
  end

  test "builds worker upload body correctly" do
    script_content = "export default { fetch() {} }"
    body = @deployer.send(:build_worker_upload_body, script_content)

    assert body["metadata"]
    assert body["index.js"]

    metadata = JSON.parse(body["metadata"])
    assert_equal "index.js", metadata["main_module"]
    assert_includes metadata["compatibility_flags"], "nodejs_compat"
  end

  test "gathers all secrets including platform and user vars" do
    # Create some app env vars if the model exists
    if @app.respond_to?(:app_env_vars)
      @app.app_env_vars.create!(
        key: "USER_VAR",
        value: "user_value",
        var_type: "user_defined"
      )
    end

    secrets = @deployer.send(:gather_all_secrets)

    assert secrets["SUPABASE_URL"]
    assert secrets["SUPABASE_SECRET_KEY"]
    assert secrets["APP_ID"]
    assert_equal @app.id.to_s, secrets["APP_ID"]
    assert secrets["OWNER_ID"]
    assert_equal @team.id.to_s, secrets["OWNER_ID"]
    assert secrets["CUSTOM_VARS"]
  end

  test "configures worker routes based on deployment type" do
    # Mock API calls
    @deployer.stub :create_or_update_route, true do
      preview_url = @deployer.send(:configure_worker_routes, "preview-app-1", :preview)
      assert_equal "https://preview-#{@app.id}.overskill.app", preview_url

      production_url = @deployer.send(:configure_worker_routes, "app-1", :production)
      assert_equal "https://app-#{@app.id}.overskill.app", production_url
    end
  end

  test "deploy_with_secrets returns success result" do
    # Mock all API calls
    @deployer.stub :deploy_worker, true do
      @deployer.stub :set_worker_secrets, true do
        @deployer.stub :configure_worker_routes, "https://preview-#{@app.id}.overskill.app" do
          result = @deployer.deploy_with_secrets(
            built_code: "test code",
            deployment_type: :preview
          )

          assert result[:success]
          assert_equal :preview, result[:deployment_type]
          assert result[:worker_url]
          assert result[:deployed_at]
        end
      end
    end
  end

  test "deploy_with_secrets handles production deployment" do
    @app.update!(custom_domain: "app.example.com")

    @deployer.stub :deploy_worker, true do
      @deployer.stub :set_worker_secrets, true do
        @deployer.stub :configure_worker_routes, "https://app-#{@app.id}.overskill.app" do
          @deployer.stub :setup_custom_domain, "app.example.com" do
            result = @deployer.deploy_with_secrets(
              built_code: "test code",
              deployment_type: :production
            )

            assert result[:success]
            assert_equal :production, result[:deployment_type]
            assert_equal "app.example.com", result[:custom_url]
          end
        end
      end
    end
  end

  test "deploy_with_secrets handles errors gracefully" do
    @deployer.stub :deploy_worker, -> { raise "API Error" } do
      result = @deployer.deploy_with_secrets(
        built_code: "test",
        deployment_type: :preview
      )

      assert_not result[:success]
      assert_equal "API Error", result[:error]
    end
  end

  test "update_secrets updates existing worker" do
    @deployer.stub :set_worker_secrets, true do
      result = @deployer.update_secrets("app-123")
      assert result
    end
  end

  test "handles API response correctly" do
    success_response = OpenStruct.new(
      success?: true,
      parsed_response: {"result" => {"id" => "123"}}
    )

    result = @deployer.send(:handle_api_response, success_response, "test operation")
    assert_equal({"id" => "123"}, result)

    error_response = OpenStruct.new(
      success?: false,
      parsed_response: {"errors" => [{"message" => "Test error"}]}
    )

    assert_raises(RuntimeError) do
      @deployer.send(:handle_api_response, error_response, "test operation")
    end
  end
end
