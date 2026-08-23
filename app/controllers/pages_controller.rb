class PagesController < ApplicationController
  def home
    @max_mb = (Artifact.max_bytes / 1.megabyte.to_f).round
    @ttl_days = Artifact.default_ttl_days
  end

  # Shared artifacts are unlisted by design; only the landing page is indexable.
  def robots
    render plain: "User-agent: *\nDisallow: /a/\nDisallow: /admin\nAllow: /\n", content_type: "text/plain"
  end
end
