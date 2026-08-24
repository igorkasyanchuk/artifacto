class PagesController < ApplicationController
  def home
    @max_mb = (Artifact.max_bytes / 1.megabyte.to_f).round
    @ttl_days = Artifact.default_ttl_days
  end

  # The skill file ships in the repo, but an agent that downloads it needs the
  # examples pointed at *this* deployment, not at artifacto.app. Rewriting on the
  # way out keeps one copy of the document instead of a template and a copy.
  SKILL_PATH = Rails.root.join("skills/artifacto/SKILL.md")
  SKILL_ORIGIN = "https://artifacto.app".freeze
  SKILL_SAMPLE_SLUG = "k3Fp9wQz2mVnB7xLd4Rs1T".freeze
  SKILL_SAMPLE_RAW_URL = "https://k3Fp9wQz2mVnB7xLd4Rs1T.artifactousercontent.com/".freeze

  def skill
    body = SKILL_PATH.read
      .gsub(SKILL_SAMPLE_RAW_URL, Artifact.new(slug: SKILL_SAMPLE_SLUG).content_url(base: request.base_url))
      .gsub(SKILL_ORIGIN, request.base_url)

    send_data body, type: "text/markdown; charset=utf-8", disposition: "attachment", filename: "SKILL.md"
  end

  # Shared artifacts are unlisted by design; only the landing page is indexable.
  def robots
    render plain: "User-agent: *\nDisallow: /a/\nDisallow: /admin\nAllow: /\n", content_type: "text/plain"
  end
end
