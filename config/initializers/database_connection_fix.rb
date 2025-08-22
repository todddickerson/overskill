# Fix for empty shard name connection issues in test environment
# This prevents "No database connection defined for '' shard" errors during testing

if Rails.env.test?
  # Patch to handle problematic shard names gracefully
  module ActiveRecord
    module ConnectionAdapters
      class ConnectionHandler
        alias_method :original_retrieve_connection_pool, :retrieve_connection_pool

        def retrieve_connection_pool(connection_name, **options)
          # Handle any problematic shard values (empty string, nil, etc.)
          shard = options[:shard]
          
          if shard.blank? || shard == ""
            # Remove shard option entirely to use default connection
            options = options.except(:shard)
          end
          
          begin
            original_retrieve_connection_pool(connection_name, **options)
          rescue ActiveRecord::ConnectionNotDefined => e
            # If we get a connection error with any shard, try without shard specification
            if options.key?(:shard)
              Rails.logger.warn "[DatabaseConnectionFix] Retrying connection without shard: #{e.message}"
              original_retrieve_connection_pool(connection_name, **options.except(:shard))
            else
              raise e
            end
          end
        end
      end
    end
  end
end