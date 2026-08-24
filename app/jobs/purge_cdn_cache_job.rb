require "net/http"

# Without this an update takes up to the edge TTL to show up. No-ops when
# Cloudflare credentials are absent, so development and tests stay offline.
class PurgeCdnCacheJob < ApplicationJob
  queue_as :default

  def perform(slug)
    zone = ENV["CF_ZONE_ID"].presence
    token = ENV["CF_API_TOKEN"].presence
    content_host = Rails.configuration.x.content_host
    return if zone.nil? || token.nil? || content_host.nil?

    url = "https://#{slug}.#{content_host}/"
    uri = URI("https://api.cloudflare.com/client/v4/zones/#{zone}/purge_cache")

    response = Net::HTTP.post(uri, { files: [ url ] }.to_json,
      "Authorization" => "Bearer #{token}", "Content-Type" => "application/json")

    Rails.logger.warn("CDN purge failed for #{slug}: #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  end
end
