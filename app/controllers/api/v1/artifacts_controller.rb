module Api
  module V1
    class ArtifactsController < ApplicationController
      include ArtifactApi

      skip_before_action :load_artifact, only: :create
      before_action :require_edit_token, only: %i[update renew destroy]
      before_action :require_pin, only: :show

      rate_limit to: 20, within: 1.hour, only: :create,
                 with: -> { too_many_requests }
      rate_limit to: 60, within: 1.hour, only: %i[update renew destroy],
                 with: -> { too_many_requests }

      rescue_from Artifact::InvalidSource do |error|
        render json: { error: error.message }, status: error.status
      end

      def create
        return render(json: { error: "file exceeds #{Artifact.max_bytes} bytes" }, status: 413) if oversized_request?

        artifact = Artifact.create_from_source!(
          uploaded_source,
          format: params[:format],
          ttl_days: params[:expires_in_days],
          title: params[:title].presence,
          allow_network: boolean(params[:allow_network]),
          pin: params[:pin].presence,
          creator_ip_hash: client_ip_hash,
          creator_ip: request.remote_ip
        )

        render json: payload(artifact, edit_token: artifact.edit_token), status: :created
      end

      def show = render(json: payload(@artifact))

      def update
        return render(json: { error: "file exceeds #{Artifact.max_bytes} bytes" }, status: 413) if oversized_request?

        @artifact.assign_source(uploaded_source, format: params[:format].presence || @artifact.format)
        @artifact.title = params[:title] if params.key?(:title)
        @artifact.allow_network = boolean(params[:allow_network]) if params.key?(:allow_network)
        @artifact.ttl_days = params[:expires_in_days]
        @artifact.save!

        PurgeCdnCacheJob.perform_later(@artifact.slug)
        render json: payload(@artifact)
      end

      # Named renew, routed as /extend: `extend` is Object#extend and must not be
      # redefined on a controller.
      def renew
        @artifact.ttl_days = params[:expires_in_days]
        @artifact.save!
        render json: payload(@artifact)
      end

      def destroy
        @artifact.destroy!
        PurgeCdnCacheJob.perform_later(@artifact.slug)
        head :no_content
      end

      private
        def oversized_request? = request.content_length.to_i > Artifact.max_bytes + 64.kilobytes

        def uploaded_source
          file = params[:file]
          return file.read if file.respond_to?(:read)
          return params[:source].to_s if params.key?(:source)
          return params[:html].to_s if params.key?(:html)

          # Only a non-form request carries the artifact as its raw body; for a form
          # post the raw body is the encoding itself, which must never be stored.
          request.form_data? ? "" : request.raw_post
        end

        def boolean(value) = ActiveModel::Type::Boolean.new.cast(value).present?

        def payload(artifact, edit_token: nil)
          {
            slug: artifact.slug,
            url: "#{Rails.configuration.x.app_origin || request.base_url}/a/#{artifact.slug}",
            raw_url: content_url_for(artifact),
            title: artifact.title,
            format: artifact.format,
            byte_size: artifact.byte_size,
            allow_network: artifact.allow_network,
            has_pin: artifact.pin?,
            view_count: artifact.view_count,
            comment_count: artifact.comments.size,
            expires_at: artifact.expires_at.utc.iso8601
          }.tap { |body| body[:edit_token] = edit_token if edit_token }
        end
    end
  end
end
