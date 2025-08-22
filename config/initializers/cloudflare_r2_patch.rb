# Apply CloudflarePreviewService R2 patch
Rails.application.config.after_initialize do
  if defined?(Patches::CloudflarePreviewServiceR2Patch)
    Patches::CloudflarePreviewServiceR2Patch.apply!
  end
end