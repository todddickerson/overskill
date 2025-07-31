# Temporary patch for CableReady 5.0.x compatibility with Rails 8
# This can be removed when BulletTrain updates to a compatible version

if defined?(CableReady::Updatable::ClassMethods)
  module CableReady
    module Updatable
      module ClassMethods
        # Define the missing constant
        class CollectionsRegistry < Hash
          def initialize
            super { |hash, key| hash[key] = [] }
          end
        end unless defined?(CollectionsRegistry)
      end
    end
  end
end