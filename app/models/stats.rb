# Read-only counters for the admin dashboard. Plain object rather than an AR
# model — nothing here is persisted, it is just a bag of COUNT queries.
class Stats
  DAYS = 14

  def artifacts = @artifacts ||= {
    total: Artifact.count,
    live: Artifact.live.count,
    blocked: Artifact.where.not(blocked_at: nil).count,
    expired: Artifact.where(expires_at: ..Time.current).count,
    today: Artifact.where(created_at: 24.hours.ago..).count,
    week: Artifact.where(created_at: 7.days.ago..).count
  }

  def users = @users ||= {
    total: User.count,
    admins: User.admins.count,
    week: User.where(created_at: 7.days.ago..).count,
    with_artifacts: Artifact.where.not(user_id: nil).distinct.count(:user_id)
  }

  def engagement = @engagement ||= {
    views: Artifact.sum(:view_count),
    comments: Comment.count,
    comments_week: Comment.where(created_at: 7.days.ago..).count,
    pending_reports: AbuseReport.pending.count,
    blocked_hashes: BlockedHash.count
  }

  def storage = @storage ||= {
    bytes: Artifact.sum(:byte_size),
    average: Artifact.average(:byte_size).to_i,
    largest: Artifact.maximum(:byte_size).to_i
  }

  def formats = @formats ||= Artifact.group(:format).count

  # Artifacts per day for the sparkline, oldest first, zero-filled so a quiet
  # day still gets a bar.
  def per_day
    @per_day ||= begin
      start = Date.current - (DAYS - 1)
      counts = Artifact.where(created_at: start.beginning_of_day..)
                       .group("DATE(created_at)").count
                       .transform_keys(&:to_date)
      (0...DAYS).map { |i| day = start + i; [ day, counts.fetch(day, 0) ] }
    end
  end

  def top_creators
    @top_creators ||= User.joins(:artifacts).group(:id).order("COUNT(artifacts.id) DESC")
                          .limit(5).count("artifacts.id")
  end
end
