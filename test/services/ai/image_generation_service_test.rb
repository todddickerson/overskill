require "test_helper"

class Ai::ImageGenerationServiceTest < ActiveSupport::TestCase
  setup do
    # Create a test app with team
    @team = Team.create!(name: "Test Team")
    @app = App.create!(
      team: @team,
      name: "Test App",
      subdomain: "test-app"
    )
    @service = Ai::ImageGenerationService.new(@app)
  end

  test "determines correct OpenAI size for square images" do
    # Square aspect ratio should use 1024x1024
    size = @service.send(:determine_openai_size, 1024, 1024)
    assert_equal "1024x1024", size

    size = @service.send(:determine_openai_size, 512, 512)
    assert_equal "1024x1024", size
  end

  test "determines correct OpenAI size for landscape images" do
    # Wide aspect ratio should use 1536x1024
    size = @service.send(:determine_openai_size, 1920, 1080)
    assert_equal "1536x1024", size

    size = @service.send(:determine_openai_size, 1600, 900)
    assert_equal "1536x1024", size
  end

  test "determines correct OpenAI size for portrait images" do
    # Tall aspect ratio should use 1024x1536
    size = @service.send(:determine_openai_size, 768, 1024)
    assert_equal "1024x1536", size

    size = @service.send(:determine_openai_size, 512, 1024)
    assert_equal "1024x1536", size
  end

  test "uses auto for in-between aspect ratios" do
    # Aspect ratios that don't clearly fit should use auto
    size = @service.send(:determine_openai_size, 1200, 1000)
    assert_equal "auto", size
  end

  test "adjusts dimensions to multiples of 32" do
    # Test dimension adjustment
    adjusted = @service.send(:adjust_to_multiple_of_32, 1080)
    assert_equal 1088, adjusted

    adjusted = @service.send(:adjust_to_multiple_of_32, 1920)
    assert_equal 1920, adjusted  # Already a multiple of 32

    adjusted = @service.send(:adjust_to_multiple_of_32, 500)
    assert_equal 512, adjusted  # Minimum is 512

    adjusted = @service.send(:adjust_to_multiple_of_32, 2000)
    assert_equal 1920, adjusted  # Maximum is 1920
  end

  test "validates image dimensions correctly" do
    # Valid dimensions (multiples of 32 within range)
    result = @service.send(:validate_dimensions, 1024, 1024)
    assert result[:valid]

    # Invalid - not multiple of 32
    result = @service.send(:validate_dimensions, 1000, 1000)
    assert result[:error]
    assert_includes result[:error], "multiples of 32"

    # Invalid - too small
    result = @service.send(:validate_dimensions, 256, 256)
    assert result[:error]
    assert_includes result[:error], "between 512 and 1920"

    # Invalid - too large
    result = @service.send(:validate_dimensions, 2048, 2048)
    assert result[:error]
    assert_includes result[:error], "between 512 and 1920"
  end

  test "generates and saves image with R2 upload" do
    # Mock the image generation and R2 upload
    mock_image_data = "fake_image_data"
    mock_r2_url = "https://pub.overskill.app/app-#{@app.id}/production/public/images/test.jpg"

    # Stub the generate_image method to return success
    @service.stub :generate_image, {
      success: true,
      image_data: mock_image_data,
      provider: "gpt-image-1"
    } do
      # Stub the R2 upload
      @service.stub :upload_image_to_r2, mock_r2_url do
        result = @service.generate_and_save_image(
          prompt: "Test image",
          target_path: "public/images/test.jpg",
          width: 1024,
          height: 1024
        )

        assert result[:success]
        assert_equal mock_r2_url, result[:url]
        assert_equal "r2", result[:storage_method]
        assert_includes result[:usage_instruction], mock_r2_url
      end
    end
  end

  test "falls back to Ideogram when OpenAI fails" do
    skip "Requires API mocking setup"
  end

  test "detects correct image content types" do
    assert_equal "image/png", @service.send(:detect_image_content_type, "test.png")
    assert_equal "image/jpeg", @service.send(:detect_image_content_type, "test.jpg")
    assert_equal "image/jpeg", @service.send(:detect_image_content_type, "test.jpeg")
    assert_equal "image/gif", @service.send(:detect_image_content_type, "test.gif")
    assert_equal "image/webp", @service.send(:detect_image_content_type, "test.webp")
    assert_equal "image/svg+xml", @service.send(:detect_image_content_type, "test.svg")
    assert_equal "image/png", @service.send(:detect_image_content_type, "test.unknown")  # Default
  end

  test "calculates correct Ideogram aspect ratios" do
    # Square
    ratio = @service.send(:calculate_ideogram_aspect_ratio, 1024, 1024)
    assert_equal "1x1", ratio

    # Landscape
    ratio = @service.send(:calculate_ideogram_aspect_ratio, 1920, 1080)
    assert_equal "16x9", ratio

    # Portrait
    ratio = @service.send(:calculate_ideogram_aspect_ratio, 1080, 1920)
    assert_equal "9x16", ratio

    # 4:3
    ratio = @service.send(:calculate_ideogram_aspect_ratio, 1600, 1200)
    assert_equal "4x3", ratio

    # 3:4
    ratio = @service.send(:calculate_ideogram_aspect_ratio, 1200, 1600)
    assert_equal "3x4", ratio
  end
end
