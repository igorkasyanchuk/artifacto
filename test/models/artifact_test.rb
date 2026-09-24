require "test_helper"

class ArtifactTest < ActiveSupport::TestCase
  HTML = "<!DOCTYPE html><html><body><h1>Hello</h1></body></html>".freeze

  test "what we serve is what was uploaded, once the injected hook is removed" do
    artifact = Artifact.create_from_source!(HTML)

    assert_equal HTML, artifact.source_html
    assert_includes artifact.served_html, "artifacto:anchor"
    assert_equal HTML.bytesize, artifact.byte_size
    assert_equal Digest::SHA256.hexdigest(HTML), artifact.sha256
  end

  test "content is stored gzipped" do
    artifact = Artifact.create_from_source!(HTML * 200)

    assert_operator artifact.content.bytesize, :<, artifact.byte_size
    assert_equal "\x1f\x8b".b, artifact.content[0, 2].b
  end

  test "rejects a body over the size limit" do
    error = assert_raises(Artifact::InvalidSource) { Artifact.create_from_source!("a" * (Artifact.max_bytes + 1)) }

    assert_equal 413, error.status
  end

  test "rejects invalid UTF-8 and empty bodies" do
    assert_raises(Artifact::InvalidSource) { Artifact.create_from_source!("\xC3\x28".b) }
    assert_raises(Artifact::InvalidSource) { Artifact.create_from_source!("") }
  end

  test "rejects a ttl outside 1..30 days" do
    assert_raises(Artifact::InvalidSource) { Artifact.create_from_source!(HTML, ttl_days: 31) }
    assert_raises(Artifact::InvalidSource) { Artifact.create_from_source!(HTML, ttl_days: 0) }
    assert_equal Artifact.default_ttl_days, Artifact.create_from_source!(HTML).ttl_days
  end

  test "markdown is rendered by us and never runs uploaded script" do
    artifact = Artifact.create_from_source!("# Title\n\n<script>alert(1)</script>\n\nhi", format: "markdown")

    assert_includes artifact.source_html, "<h1>"
    assert_not_includes artifact.source_html, "alert(1)"
  end

  test "edit token is compared against its digest only" do
    artifact = Artifact.create_from_source!(HTML)

    assert artifact.authenticate_edit_token(artifact.edit_token)
    assert_not artifact.authenticate_edit_token("wrong")
    assert_not artifact.authenticate_edit_token(nil)
    assert_not_equal artifact.edit_token, artifact.edit_token_digest
  end

  test "re-uploading blocked bytes is refused" do
    artifact = Artifact.create_from_source!(HTML)
    BlockedHash.record_artifact!(artifact, reason: "test")

    error = assert_raises(Artifact::InvalidSource) { Artifact.create_from_source!(HTML) }
    assert_equal 451, error.status
  end

  test "an image from a blocked artifact is refused inside a different page" do
    image = "data:image/png;base64,#{Base64.strict_encode64('not really a png')}"
    blocked = Artifact.create_from_source!("<html><body><img src=\"#{image}\"></body></html>")
    BlockedHash.record_artifact!(blocked, reason: "test")

    error = assert_raises(Artifact::InvalidSource) do
      Artifact.create_from_source!("<html><body><h1>reskinned</h1><img src=\"#{image}\"></body></html>")
    end

    assert_equal 451, error.status
  end

  test "the uploader IP is stored encrypted, not in the clear" do
    artifact = Artifact.create_from_source!(HTML, creator_ip: "203.0.113.9")
    stored = Artifact.connection.select_value("select creator_ip from artifacts where id = #{artifact.id}")

    assert_not_includes stored, "203.0.113.9"
    assert_equal "203.0.113.9", artifact.reload.creator_ip
  end

  test "slug is long, and lowercase so it survives being a hostname" do
    slug = Artifact.create_from_source!(HTML).slug

    assert_equal 22, slug.length
    assert_equal slug.downcase, slug
    assert_match(/\A[a-z0-9]+\z/, slug)
  end

  test "an artifact still carrying an older hook is re-spliced with the current one" do
    artifact = Artifact.create_from_source!(HTML)
    stale = artifact.served_html.sub(AgentInjector::BLOCK,
      "#{AgentInjector::OPEN_MARKER}<script>/* the hook as it shipped last release */</script>#{AgentInjector::CLOSE_MARKER}")
    artifact.update_column(:content, Artifact.gzip(stale))

    assert artifact.refresh_agent_hook!
    artifact.reload

    assert_includes artifact.served_html, AgentInjector.script
    assert_equal HTML, artifact.source_html, "the uploaded source is untouched"
    assert_equal Digest::SHA256.hexdigest(HTML), artifact.sha256
  end

  test "refreshing an artifact that already has the current hook changes nothing" do
    artifact = Artifact.create_from_source!(HTML)

    assert_not artifact.refresh_agent_hook!
  end

  test "a Markdown artifact's CSP hash matches the script it actually carries after a refresh" do
    artifact = Artifact.create_from_source!("# hi\n\nsome text", format: "markdown")
    stale = artifact.served_html.sub(AgentInjector::BLOCK,
      "#{AgentInjector::OPEN_MARKER}<script>/* last release */</script>#{AgentInjector::CLOSE_MARKER}")
    artifact.update_column(:content, Artifact.gzip(stale))

    inline = ->(html) { html[%r{<script>(.*?)</script>}m, 1] }
    hash_of = ->(script) { "'sha256-#{Base64.strict_encode64(Digest::SHA256.digest(script))}'" }

    assert_not_equal AgentInjector.csp_hash, hash_of.call(inline.call(artifact.reload.served_html)),
      "a stale Markdown body is served a hash that does not cover its own script"

    artifact.refresh_agent_hook!

    assert_equal AgentInjector.csp_hash, hash_of.call(inline.call(artifact.reload.served_html))
  end

  test "a PIN must be long enough to guess slowly and short enough for bcrypt to read whole" do
    artifact = Artifact.create_from_source!(HTML)

    assert_raises(ActiveRecord::RecordInvalid) { artifact.update!(pin: "1234") }
    assert_raises(ActiveRecord::RecordInvalid) { artifact.update!(pin: "ж" * 40) }
    assert artifact.update!(pin: "123456")
    assert_includes Artifact.new(pin: "1").tap(&:validate).errors.full_messages.first, "PIN"
  end
end
