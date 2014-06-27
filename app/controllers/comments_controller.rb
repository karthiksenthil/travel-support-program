class CommentsController < ApplicationController
  respond_to :json, :js
  skip_load_and_authorize_resource
  before_filter :load_command_and_authorize

  def create
    @comment.user = current_user
    @comment.save
    respond_with(@comment) do |format|
      format.js {
        if @comment.valid?
          flash[:notice] = t("comment_added")
          render :create
        else
          flash[:error] = t("comment_failed")
          flash.discard # Using JS responses, must be discarded manually
          render :new
        end
      }
    end
  end

  protected

  def load_command_and_authorize
    prepare_for_nested_resource
    if action_name.to_sym == :new
      @comment = @parent.comments.build(:private => Comment.private_role?(current_user.profile.role_name, @parent.class))
    else
      @comment = @parent.comments.build(:body => params[:comment][:body],
                                        :private => params[:comment][:private])
    end
    authorize! :create, @comment
  end
end
