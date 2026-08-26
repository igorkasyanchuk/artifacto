module Admin
  # Comments are user text on the app's own origin, which `blocked_hashes` does
  # not cover — that list is about artifact bytes. Moderation here is a delete.
  class CommentsController < BaseController
    def index
      @comments = Comment.includes(:artifact).order(created_at: :desc).limit(200)
    end

    def destroy
      Comment.find(params[:id]).destroy!
      redirect_to admin_comments_path, notice: "Comment deleted."
    end
  end
end
