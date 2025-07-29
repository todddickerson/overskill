# Ensure service modules are loaded
Rails.application.config.to_prepare do
  Dir[Rails.root.join("app/services/**/*.rb")].each { |f| require f }
end