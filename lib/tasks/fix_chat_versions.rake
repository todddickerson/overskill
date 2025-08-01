namespace :overskill do
  desc "Fix chat message version associations"
  task fix_chat_versions: :environment do
    puts "Fixing chat message version associations..."
    
    fixed_count = 0
    
    # Find assistant messages that don't have app_version_id set but should
    AppChatMessage.where(role: 'assistant', app_version_id: nil, status: 'completed').find_each do |message|
      # Find the version created around the same time as this message
      # Look for versions created within 5 minutes of the message
      time_range = (message.created_at - 5.minutes)..(message.created_at + 5.minutes)
      
      version = message.app.app_versions.where(created_at: time_range).order(created_at: :desc).first
      
      if version
        message.update!(app_version: version)
        puts "Fixed message #{message.id} -> version #{version.version_number}"
        fixed_count += 1
      else
        puts "No version found for message #{message.id} (created at #{message.created_at})"
      end
    end
    
    puts "Fixed #{fixed_count} chat messages"
  end
end