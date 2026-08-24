# The wrapper page on the app host: branding, report button, TTL, and in phase 2
# the comment overlay. It never renders artifact HTML itself — that always comes
# from the content origin inside an iframe.
class ArtifactsController < ApplicationController
  UNLOCK_WINDOW = 10.minutes

  before_action :load_artifact

  def show
    @unlock_token = valid_unlock_token
    @needs_pin = @artifact.pin? && @unlock_token.nil?
    @iframe_src = content_url_for(@artifact, token: @unlock_token) unless @needs_pin
  end

  def unlock
    if @artifact.pin? && @artifact.authenticate_pin(params[:pin].to_s)
      redirect_to artifact_path(@artifact.slug, k: pin_verifier.generate(@artifact.slug, expires_in: UNLOCK_WINDOW))
    else
      @needs_pin = true
      flash.now[:alert] = "Wrong PIN."
      render :show, status: :unauthorized
    end
  end

  private
    def load_artifact
      @artifact = Artifact.find_by(slug: params[:slug])
      return render(:missing, status: :not_found) if @artifact.nil?
      return render(:blocked, status: :unavailable_for_legal_reasons) if @artifact.blocked?
      render(:expired, status: :gone) if @artifact.expired?
    end

    # Re-minted rather than passed through: the token the reader arrived with may
    # be seconds from expiring, and the comment overlay holds on to it for as
    # long as the page stays open. A reload therefore buys a fresh window.
    def valid_unlock_token
      return nil unless @artifact.pin?
      return nil unless pin_verifier.verified(params[:k].to_s) == @artifact.slug

      pin_verifier.generate(@artifact.slug, expires_in: UNLOCK_WINDOW)
    end
end
