module Api
  module V1
    # Anonymous, like upload: whoever holds the link can comment. Identity is an
    # IP hash for moderation and nothing else until accounts exist.
    class CommentsController < ApplicationController
      include ArtifactApi

      before_action :require_pin
      before_action :require_edit_token, only: :destroy

      rate_limit to: 20, within: 1.hour, only: :create, with: -> { too_many_requests }

      rescue_from ActiveRecord::RecordInvalid do |error|
        render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end

      def index = render(json: { comments: @artifact.comments.oldest_first.as_json })

      def create
        if @artifact.comments.count >= Comment::MAX_PER_ARTIFACT
          return render(json: { error: "this artifact has all the comments it can hold" }, status: :too_many_requests)
        end

        comment = @artifact.comments.create!(
          selector: params[:selector].to_s.truncate(Comment::MAX_SELECTOR),
          quote: params[:quote].to_s.truncate(Comment::MAX_QUOTE),
          body: params[:body].to_s.strip.truncate(Comment::MAX_BODY),
          author: params[:author].to_s.strip.presence&.truncate(Comment::MAX_AUTHOR),
          anchor_x: Comment.fraction(params[:anchor_x]),
          anchor_y: Comment.fraction(params[:anchor_y]),
          author_ip_hash: client_ip_hash
        )

        render json: comment.as_json, status: :created
      end

      # Owner cleanup: the agent that wrote the artifact acts on the feedback and
      # then clears it. Site-wide moderation lives in /admin.
      def destroy
        @artifact.comments.find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
