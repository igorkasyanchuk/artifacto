module Admin
  class ArtifactsController < BaseController
    def index
      @reported = Artifact.joins(:abuse_reports).merge(AbuseReport.pending).distinct.order(created_at: :desc)
      @recent = Artifact.order(created_at: :desc).limit(50)
    end

    def block
      artifact = Artifact.find_by!(slug: params[:slug])
      artifact.update!(blocked_at: Time.current)
      BlockedHash.record_artifact!(artifact, reason: "admin-block")
      artifact.abuse_reports.pending.update_all(handled_at: Time.current)
      PurgeCdnCacheJob.perform_later(artifact.slug)
      redirect_to admin_artifacts_path, notice: "Blocked #{artifact.slug}."
    end

    def destroy
      artifact = Artifact.find_by!(slug: params[:slug])
      artifact.destroy!
      PurgeCdnCacheJob.perform_later(artifact.slug)
      redirect_to admin_artifacts_path, notice: "Deleted #{artifact.slug}."
    end
  end
end
