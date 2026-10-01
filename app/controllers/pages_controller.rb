class PagesController < ApplicationController
  # Analytics runs on these pages alone, so only they open the policy to it —
  # on top of the app-wide sources, not instead of them.
  content_security_policy do |policy|
    if analytics?
      origin = Rails.configuration.x.umami_origin
      policy.script_src(*policy.directives["script-src"], origin)
      policy.connect_src(*policy.directives["connect-src"], origin)
    end
  end

  helper_method :analytics?

  def home
    @max_mb = (Artifact.max_bytes / 1.megabyte.to_f).round
    @ttl_days = Artifact.default_ttl_days
  end

  # The skill file ships in the repo, but an agent that downloads it needs the
  # examples pointed at *this* deployment, not at the public instance. Rewriting
  # on the way out keeps one copy of the document instead of a template and a copy.
  SKILL_PATH = Rails.root.join("skills/artifacto/SKILL.md")
  SKILL_ORIGIN = "https://artifacto.igorkasyanchuk.com".freeze
  SKILL_SAMPLE_SLUG = "k3Fp9wQz2mVnB7xLd4Rs1T".freeze
  SKILL_SAMPLE_RAW_URL = "https://k3Fp9wQz2mVnB7xLd4Rs1T.artifactousercontent.com/".freeze

  def skill
    body = SKILL_PATH.read
      .gsub(SKILL_SAMPLE_RAW_URL, Artifact.new(slug: SKILL_SAMPLE_SLUG).content_url(base: request.base_url))
      .gsub(SKILL_ORIGIN, request.base_url)

    send_data body, type: "text/markdown; charset=utf-8", disposition: "attachment", filename: "SKILL.md"
  end

  # Where abuse reports and legal notices go. Unset, the page points at the
  # Report form alone.
  def terms
    @abuse_email = ENV["ABUSE_EMAIL"].presence
  end

  # Shared artifacts are unlisted by design; only the landing page is indexable.
  def robots
    render plain: "User-agent: *\nDisallow: /a/\nDisallow: /raw/\nDisallow: /admin\nAllow: /\n", content_type: "text/plain"
  end

  private
    def analytics?
      Rails.configuration.x.umami_origin.present?
    end
end
