# Shared by the API controllers that address one artifact: the same lookup, the
# same 404 / 451 / 410 answers, and the same bearer-token check.
module ArtifactApi
  extend ActiveSupport::Concern

  included do
    skip_forgery_protection
    before_action :load_artifact

    # Every other failure in this namespace answers in JSON; a bad id must not be
    # the one that hands a client Rails' HTML error page.
    rescue_from ActiveRecord::RecordNotFound do
      render json: { error: "not found" }, status: :not_found
    end

    rescue_from ActiveRecord::RecordInvalid do |error|
      render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private
    # Nested routes carry :artifact_slug, the artifact's own routes carry :slug.
    def load_artifact
      @artifact = Artifact.find_by(slug: params[:artifact_slug] || params[:slug])
      return render(json: { error: "not found" }, status: :not_found) if @artifact.nil?
      return render(json: { error: "blocked" }, status: :unavailable_for_legal_reasons) if @artifact.blocked?
      render(json: { error: "expired" }, status: :gone) if @artifact.expired?
    end

    # A PIN gates the artifact, so it has to gate everything derived from it: a
    # stored quote is up to 200 characters lifted straight out of the locked page.
    # Same short-lived signed token the content zone takes, minted on the wrapper
    # page once the PIN has been entered.
    def require_pin
      return unless @artifact.pin?
      return if pin_verifier.verified(params[:t].to_s) == @artifact.slug
      # The edit token outranks the PIN: whoever published the artifact set it.
      return if @artifact.authenticate_edit_token(bearer_token)

      render json: { error: "pin required" }, status: :unauthorized
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
