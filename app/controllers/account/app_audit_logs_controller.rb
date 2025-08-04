class Account::AppAuditLogsController < Account::ApplicationController
  before_action :set_app
  before_action :authorize_audit_access
  
  def index
    @audit_service = Security::AuditLogService.new(@app)
    
    @logs = @audit_service.get_recent_activity(
      limit: params[:limit] || 50,
      offset: params[:offset] || 0
    )
    
    @summary = @audit_service.get_activity_summary(24.hours)
    
    respond_to do |format|
      format.html
      format.json { render json: { logs: @logs, summary: @summary } }
      format.csv do
        send_data generate_csv(@logs),
                  filename: "#{@app.slug}_audit_log_#{Date.current}.csv",
                  type: 'text/csv'
      end
    end
  end
  
  def show
    @audit_service = Security::AuditLogService.new(@app)
    
    # Show audit trail for specific record
    @logs = @audit_service.get_activity_by_record(
      params[:table_name],
      params[:id]
    )
    
    @record_history = build_record_history(@logs)
  end
  
  def search
    @audit_service = Security::AuditLogService.new(@app)
    
    @results = @audit_service.search_audit_logs(
      params[:q],
      limit: params[:limit] || 50
    )
    
    render partial: "search_results", locals: { logs: @results }
  end
  
  def compliance_report
    @audit_service = Security::AuditLogService.new(@app)
    @report = @audit_service.get_compliance_report
    
    respond_to do |format|
      format.html
      format.json { render json: @report }
      format.pdf do
        # Generate compliance PDF
        pdf = ComplianceReportPdf.new(@report, @app)
        send_data pdf.render,
                  filename: "#{@app.slug}_compliance_report_#{Date.current}.pdf",
                  type: 'application/pdf'
      end
    end
  end
  
  def export
    @audit_service = Security::AuditLogService.new(@app)
    
    export_data = @audit_service.export_audit_trail(
      start_date: params[:start_date]&.to_date || 30.days.ago,
      end_date: params[:end_date]&.to_date || Date.current
    )
    
    respond_to do |format|
      format.json do
        send_data export_data.to_json,
                  filename: "#{@app.slug}_audit_export_#{Date.current}.json",
                  type: 'application/json'
      end
    end
  end
  
  private
  
  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
  
  def authorize_audit_access
    # Only team admins can view audit logs
    unless can?(:manage, @team)
      redirect_to account_app_path(@app), 
                  alert: "You don't have permission to view audit logs"
    end
  end
  
  def generate_csv(logs)
    CSV.generate(headers: true) do |csv|
      csv << ['Timestamp', 'Table', 'Operation', 'User', 'Record ID', 'Changes']
      
      logs.each do |log|
        csv << [
          log['created_at'],
          log['table_name'],
          log['operation'],
          log['user_id'],
          log['record_id'],
          log['data'].to_json
        ]
      end
    end
  end
  
  def build_record_history(logs)
    # Build a timeline of changes for a record
    logs.map do |log|
      {
        timestamp: log['created_at'],
        operation: log['operation'],
        user: get_user_name(log['user_id']),
        changes: format_changes(log['data'], log['operation'])
      }
    end
  end
  
  def get_user_name(user_id)
    User.find_by(id: user_id)&.name || "User #{user_id}"
  end
  
  def format_changes(data, operation)
    case operation
    when 'INSERT'
      "Created with: #{data['new'].to_json}"
    when 'UPDATE'
      changed = data['changed_fields']&.keys&.join(', ') || 'unknown fields'
      "Updated: #{changed}"
    when 'DELETE'
      "Deleted record"
    else
      data.to_json
    end
  end
end