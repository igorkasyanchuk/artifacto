class AbuseReportsController < ApplicationController
  rate_limit to: 10, within: 1.hour,
             with: -> { redirect_to artifact_path(params[:slug]), alert: "Too many reports, try later." }

  def create
    artifact = Artifact.find_by(slug: params[:slug])
    return head :not_found if artifact.nil?

    artifact.abuse_reports.create!(
      reason: AbuseReport::REASONS.include?(params[:reason]) ? params[:reason] : "other",
      details: params[:details].to_s.truncate(2_000),
      reporter_ip_hash: client_ip_hash
    )

    redirect_to artifact_path(artifact.slug), notice: "Reported. Thank you."
  end
end
