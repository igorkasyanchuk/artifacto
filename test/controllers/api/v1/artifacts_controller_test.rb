require "test_helper"

module Api
  module V1
    class ArtifactsControllerTest < ActionDispatch::IntegrationTest
      HTML = "<!DOCTYPE html><html><body><p>v1</p></body></html>".freeze

      setup { host! Rails.configuration.x.app_host }

      # Rack caps urlencoded bodies at 4 MB, so anything near the 5 MB limit has to
      # arrive as multipart or as a raw body — which is what the skill and docs use.
      def upload(content, name: "page.html", type: "text/html")
        file = Tempfile.new([ "artifact", File.extname(name) ], binmode: true)
        file.write(content)
        file.rewind
        Rack::Test::UploadedFile.new(file.path, type, original_filename: name)
      end

      test "creates an artifact and returns the edit token once" do
        post "/api/v1/artifacts", params: { source: HTML, title: "Report" }

        assert_response :created
        body = response.parsed_body
        assert_equal 22, body["slug"].length
        assert_equal 32, body["edit_token"].length
        assert_includes body["raw_url"], body["slug"]
        assert_equal HTML.bytesize, body["byte_size"]

        get "/api/v1/artifacts/#{body['slug']}"
        assert_response :success
        assert_nil response.parsed_body["edit_token"]
      end

      test "accepts a file right at the size limit over multipart" do
        body = "<html><body>#{'x' * (Artifact.max_bytes - 40)}</body></html>"
        assert_operator body.bytesize, :<=, Artifact.max_bytes

        post "/api/v1/artifacts", params: { file: upload(body) }

        assert_response :created
        assert_equal body.bytesize, response.parsed_body["byte_size"]
      end

      test "accepts a raw request body" do
        post "/api/v1/artifacts", params: HTML, headers: { "CONTENT_TYPE" => "text/html" }

        assert_response :created
        assert_equal HTML, Artifact.find_by(slug: response.parsed_body["slug"]).source_html
      end

      test "rejects oversized and malformed bodies" do
        post "/api/v1/artifacts", params: { file: upload("a" * (Artifact.max_bytes + 1)) }
        assert_response 413

        post "/api/v1/artifacts", params: { source: "" }
        assert_response :unprocessable_entity

        post "/api/v1/artifacts", params: { source: HTML, expires_in_days: 99 }
        assert_response :unprocessable_entity
      end

      test "update needs the right token and resets the clock" do
        artifact = Artifact.create_from_source!(HTML)
        token = artifact.edit_token
        artifact.update_column(:expires_at, 2.days.from_now)

        put "/api/v1/artifacts/#{artifact.slug}", params: { source: "<html><body>new</body></html>" }
        assert_response :unauthorized

        put "/api/v1/artifacts/#{artifact.slug}",
            params: { source: "<html><body>new</body></html>" },
            headers: { "Authorization" => "Bearer #{token}" }
        assert_response :success

        artifact.reload
        assert_includes artifact.source_html, "new"
        assert_operator artifact.expires_at, :>, 10.days.from_now
      end

      test "extend pushes the expiry out without touching the body" do
        artifact = Artifact.create_from_source!(HTML, ttl_days: 1)
        token = artifact.edit_token

        patch "/api/v1/artifacts/#{artifact.slug}/extend",
              params: { expires_in_days: 30 },
              headers: { "Authorization" => "Bearer #{token}" }

        assert_response :success
        assert_equal HTML, artifact.reload.source_html
        assert_operator artifact.expires_at, :>, 29.days.from_now
      end

      test "delete removes it for good" do
        artifact = Artifact.create_from_source!(HTML)

        delete "/api/v1/artifacts/#{artifact.slug}", headers: { "Authorization" => "Bearer #{artifact.edit_token}" }

        assert_response :no_content
        assert_nil Artifact.find_by(slug: artifact.slug)
      end

      test "expired and blocked artifacts are not addressable" do
        expired = Artifact.create_from_source!(HTML)
        expired.update_column(:expires_at, 1.hour.ago)
        get "/api/v1/artifacts/#{expired.slug}"
        assert_response :gone

        blocked = Artifact.create_from_source!(HTML)
        blocked.update!(blocked_at: Time.current)
        get "/api/v1/artifacts/#{blocked.slug}"
        assert_response :unavailable_for_legal_reasons
      end
    end
  end
end
