class Account::AppSecurityPoliciesController < Account::ApplicationController
  before_action :set_app
  
  def index
    @policy_service = Security::RlsPolicyService.new(@app)
    @policies = @policy_service.get_all_policies
    @security_functions = @policy_service.get_security_functions
    @audit_config = @policy_service.get_audit_configuration
    @security_report = @policy_service.generate_security_report
    
    respond_to do |format|
      format.html
      format.json { render json: @security_report }
      format.pdf do
        # Generate PDF report for compliance
        pdf = SecurityReportPdf.new(@security_report)
        send_data pdf.render,
                  filename: "#{@app.slug}_security_report_#{Date.current}.pdf",
                  type: 'application/pdf',
                  disposition: 'inline'
      end
    end
  end
  
  def show
    @policy_service = Security::RlsPolicyService.new(@app)
    @policy = @policy_service.get_all_policies.find { |p| p[:name] == params[:id] }
    
    if @policy
      @explanation = @policy_service.explain_policy(@policy[:name])
    else
      redirect_to account_app_security_policies_path(@app), 
                  alert: "Policy not found"
    end
  end
  
  private
  
  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
end