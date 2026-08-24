class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  private
    def client_ip_hash = Artifact.hash_ip(request.remote_ip)

    def content_url_for(artifact, token: nil) = artifact.content_url(base: request.base_url, token: token)

    def pin_verifier = Rails.application.message_verifier(:artifact_pin)
end
