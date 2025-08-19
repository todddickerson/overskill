require_relative 'config/environment'

app = App.find(1025)
puts "Redeploying App: #{app.name} (ID: #{app.id})"

# Clear the previous error state
app.update!(status: 'ready')

# First build the app for preview
builder = Deployment::ExternalViteBuilder.new(app)
build_result = builder.build_for_preview

if build_result[:success]
  puts "✅ Build successful"
  
  # Then deploy it
  deployer = Deployment::CloudflareWorkersDeployer.new(app)
  deploy_result = deployer.deploy_with_secrets(
    built_code: build_result[:built_code],
    deployment_type: :preview
  )
  
  if deploy_result[:success]
    puts "✅ Deployment SUCCESS!"
    puts "Preview URL: #{deploy_result[:preview_url]}"
    app.update!(preview_url: deploy_result[:preview_url], status: 'ready')
  else
    puts "❌ Deployment FAILED"
    puts "Error: #{deploy_result[:error]}"
  end
else
  puts "❌ Build FAILED"
  puts "Error: #{build_result[:error]}"
end
