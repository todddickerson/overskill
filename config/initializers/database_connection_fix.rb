# Fix for empty shard name connection issues in test environment
# This prevents "No database connection defined for '' shard" errors during testing

if Rails.env.test?
  # Patch to handle empty shard names gracefully
  module ActiveRecord
    module ConnectionAdapters
      class ConnectionHandler
        alias_method :original_retrieve_connection_pool, :retrieve_connection_pool

        def retrieve_connection_pool(connection_name, **options)
          # If shard is an empty string, default to primary connection
          if options[:shard] == ""
            options[:shard] = :primary
          end
          
          original_retrieve_connection_pool(connection_name, **options)
        end
      end
    end
  end
end