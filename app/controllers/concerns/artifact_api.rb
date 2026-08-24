# Shared by the API controllers that address one artifact: the same lookup, the
# same 404 / 451 / 410 answers, and the same bearer-token check.
module ArtifactApi
  extend ActiveSupport::Concern

  included do
    skip_forgery_protection
    before_action :load_artifact
  end

  private
    # Nested routes carry :artifact_slug, the artifact's own routes carry :slug.
    def load_artifact
      @artifact = Artifact.find_by(slug: params[:artifact_slug] || params[:slug])
      return render(json: { error: "not found" }, status: :not_found) if @artifact.nil?
      return render(json: { error: "blocked" }, status: :unavailable_for_legal_reasons) if @artifact.blocked?
      render(json: { error: "expired" }, status: :gone) if @artifact.expired?
    end

    def require_edit_token
      return if @artifact.authenticate_edit_token(bearer_token)

      render json: { error: "invalid edit token" }, status: :unauthorized
    end

    def bearer_token = request.headers["Authorization"].to_s[/\ABearer (.+)\z/, 1]

    def too_many_requests
      render json: { error: "rate limit exceeded" }, status: :too_many_requests
    end
end
