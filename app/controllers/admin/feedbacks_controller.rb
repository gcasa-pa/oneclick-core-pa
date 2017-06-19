class Admin::FeedbacksController < Admin::AdminController

  def index
    @feedbacks = Feedback.pending
  end
  
  def acknowledged
    @feedbacks = Feedback.acknowledged
  end
  
  def show
    @feedback = Feedback.find(params[:id])
    @acknowledgement_comment = @feedback.acknowledgement_comment || @feedback.build_acknowledgement_comment(
      commenter: current_user, 
      locale: current_user.preferred_locale.try(:name)
    )
  end
  
  def update
    @feedback = Feedback.find(params[:id])
    
    if @feedback.update_attributes(feedback_params)
      if @feedback.acknowledged?
        flash[:success] = "Feedback successfully acknowledged"
        redirect_to admin_feedback_path(@feedback)
      else
        flash[:success] = "Feedback reopened"
        redirect_to admin_feedback_path(@feedback)
      end
    else
      flash[:danger] = @feedback.errors.full_messages.to_sentence
      redirect_to admin_feedback_path(@feedback)
    end
    
  end
  
  private
  
  def feedback_params
    params.require(:feedback).permit(
      :acknowledged,
      acknowledgement_comment_attributes: [:comment, :commenter_id, :locale, :id]
    )
  end

end