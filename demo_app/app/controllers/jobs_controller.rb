class JobsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def new
  end

  def create
    if params[:worker].blank?
      flash[:error] = 'No worker type selected'
    else
      jid = params[:worker].constantize.perform_async
      flash[:success] = "Kicked off a workflow with jid #{jid}"
    end

    redirect_to new_job_path
  end
end
