module Api
  module V1
    class IframeBridgeController < Api::V1::ApplicationController
      before_action :find_app
      before_action :validate_app_access, except: [:log] # Allow logs from deployed apps
      
      # POST /api/v1/iframe_bridge/:app_id/log
      # Receives console logs and network requests from deployed iframe apps
      def log
        bridge_service = Deployment::IframeBridgeService.new(@app)
        
        case params[:type]
        when 'console'
          bridge_service.store_console_log(params[:data])
        when 'network'
          bridge_service.store_network_request(params[:data])
        else
          return render json: { error: 'Invalid log type' }, status: :bad_request
        end
        
        render json: { success: true }
      rescue => e
        Rails.logger.error "[IframeBridge] Error storing #{params[:type]} log: #{e.message}"
        render json: { error: 'Failed to store log' }, status: :internal_server_error
      end
      
      # GET /api/v1/iframe_bridge/:app_id/console_logs
      # AI access to console logs for debugging
      def console_logs
        bridge_service = Deployment::IframeBridgeService.new(@app)
        result = bridge_service.read_console_logs(params[:search], params[:limit]&.to_i)
        
        if result[:success]
          render json: result
        else
          render json: { error: result[:error] }, status: :internal_server_error
        end
      end
      
      # GET /api/v1/iframe_bridge/:app_id/network_requests
      # AI access to network requests for debugging
      def network_requests
        bridge_service = Deployment::IframeBridgeService.new(@app)
        result = bridge_service.read_network_requests(params[:search], params[:limit]&.to_i)
        
        if result[:success]
          render json: result
        else
          render json: { error: result[:error] }, status: :internal_server_error
        end
      end
      
      # POST /api/v1/iframe_bridge/:app_id/setup
      # Setup bridge code for deployment
      def setup
        bridge_service = Deployment::IframeBridgeService.new(@app)
        result = bridge_service.setup_console_bridge
        
        if result[:success]
          render json: result
        else
          render json: { error: 'Failed to setup bridge' }, status: :internal_server_error
        end
      end
      
      # DELETE /api/v1/iframe_bridge/:app_id/clear
      # Clear debugging data for privacy
      def clear
        bridge_service = Deployment::IframeBridgeService.new(@app)
        bridge_service.clear_debugging_data
        
        render json: { success: true, message: 'Debugging data cleared' }
      end
      
      private
      
      def find_app
        @app = App.find(params[:app_id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'App not found' }, status: :not_found
      end
      
      def validate_app_access
        # Check if current user has access to this app
        # For log endpoint, we allow access from the deployed app itself
        unless current_user&.can_access_app?(@app)
          render json: { error: 'Access denied' }, status: :forbidden
        end
      end
    end
  end
end