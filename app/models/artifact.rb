require "zlib"
require "stringio"

class Artifact < ApplicationRecord
  # Raised for anything wrong with the uploaded body. Carries the HTTP status the
  # API should answer with, so controllers stay a single rescue.
  class InvalidSource < StandardError
    attr_reader :status

    def initialize(message, status)
      super(message)
      @status = status
    end
  end

  FORMATS = %w[html markdown].freeze
  SLUG_LENGTH = 22
  TTL_DAYS = (1..30)

  has_many :abuse_reports, dependent: :delete_all

  encrypts :creator_ip

  IP_RETENTION = 30.days

  # Gives us #pin=, #pin_digest and #authenticate_pin without hand-rolling bcrypt.
  has_secure_password :pin, validations: false

  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9]{#{SLUG_LENGTH}}\z/ }
  validates :format, inclusion: { in: FORMATS }
  validates :content, :edit_token_digest, :expires_at, presence: true

  scope :live, -> { where(blocked_at: nil).where(expires_at: Time.current..) }

  def self.max_bytes = ENV.fetch("MAX_UPLOAD_BYTES", 5.megabytes).to_i
  def self.default_ttl_days = ENV.fetch("DEFAULT_TTL_DAYS", 14).to_i

  # Lowercase only: the slug is part of a hostname and browsers normalise those to
  # lowercase, so a mixed-case slug would never resolve. 22 chars of [a-z0-9] is
  # still ~113 bits — this is what stands in for a login.
  SLUG_ALPHABET = [ *"a".."z", *"0".."9" ].freeze

  def self.generate_slug = SecureRandom.alphanumeric(SLUG_LENGTH, chars: SLUG_ALPHABET)
  def self.generate_edit_token = SecureRandom.alphanumeric(32)
  def self.digest_token(token) = Digest::SHA256.hexdigest(token.to_s)

  # Every base64 image in the body, hashed. Used both to reject known-bad uploads
  # and to seed the blocklist when an artifact is taken down.
  DATA_IMAGE = %r{data:image/[a-z.+-]+;base64,([A-Za-z0-9+/=]+)}i

  def self.embedded_image_digests(html)
    html.to_s.scan(DATA_IMAGE).flatten.map { |payload| Digest::SHA256.hexdigest(payload) }.uniq
  end

  def self.hash_ip(ip)
    OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("IP_HASH_SECRET", "dev-secret"), ip.to_s)
  end

  # The plaintext edit token, available only on the instance that just created it.
  attr_reader :edit_token

  def self.create_from_source!(source, format: "html", ttl_days: nil, **attrs)
    artifact = new(attrs)
    artifact.slug = generate_slug
    artifact.assign_edit_token
    artifact.ttl_days = ttl_days
    artifact.assign_source(source, format: format)
    artifact.save!
    artifact
  end

  def assign_edit_token
    @edit_token = self.class.generate_edit_token
    self.edit_token_digest = self.class.digest_token(@edit_token)
  end

  def authenticate_edit_token(token)
    return false if token.blank?

    ActiveSupport::SecurityUtils.secure_compare(edit_token_digest, self.class.digest_token(token))
  end

  def ttl_days=(days)
    days = (days.presence || self.class.default_ttl_days).to_i
    raise InvalidSource.new("expires_in_days must be between 1 and 30", :unprocessable_entity) unless TTL_DAYS.cover?(days)

    self.expires_at = days.days.from_now
  end

  def ttl_days = ((expires_at - Time.current) / 1.day).ceil

  # Validates, renders and compresses in one shot. The agent hook is injected here
  # rather than on every request, so serving is a straight byte dump.
  def assign_source(source, format: "html")
    format = format.presence || "html"
    raise InvalidSource.new("unknown format", :unprocessable_entity) unless FORMATS.include?(format)

    source = source.to_s.dup.force_encoding(Encoding::UTF_8)
    raise InvalidSource.new("file is empty", :unprocessable_entity) if source.empty?
    raise InvalidSource.new("file is not valid UTF-8", :unprocessable_entity) unless source.valid_encoding?
    raise InvalidSource.new("file exceeds #{self.class.max_bytes} bytes", 413) if source.bytesize > self.class.max_bytes

    digests = [ Digest::SHA256.hexdigest(source) ] + self.class.embedded_image_digests(source)
    raise InvalidSource.new("content is blocked", 451) if BlockedHash.blocks?(digests)

    self.format = format
    self.byte_size = source.bytesize
    self.sha256 = digests.first
    self.content = self.class.gzip(AgentInjector.inject(render(source)))
  end

  # Uncompressed body exactly as browsers receive it (agent hook included).
  def served_html = self.class.gunzip(content)

  # What was uploaded, recovered from what we serve. Used by the integrity test.
  def source_html = AgentInjector.strip(served_html)

  def expired? = expires_at <= Time.current
  def blocked? = blocked_at.present?
  def pin? = pin_digest.present?

  def etag = %("#{sha256[0, 16]}-#{AgentInjector::VERSION}")

  def content_url(token: nil)
    config = Rails.configuration.x
    host = "#{slug}.#{config.content_host}"
    host = "#{host}:#{config.content_port}" if config.content_port
    url = "#{config.content_scheme}://#{host}/"
    token ? "#{url}?t=#{CGI.escape(token)}" : url
  end

  def self.gzip(string)
    io = StringIO.new(+"", "wb")
    writer = Zlib::GzipWriter.new(io, Zlib::BEST_COMPRESSION)
    writer.write(string)
    writer.close
    io.string
  end

  def self.gunzip(bytes)
    Zlib::GzipReader.new(StringIO.new(bytes.to_s.b)).read.force_encoding(Encoding::UTF_8)
  end

  private
    # HTML is served untouched — sanitizing it would break every interactive
    # artifact. Isolation (separate origin + CSP) is the boundary, not scrubbing.
    # Markdown is ours, so we render and sanitize it and it never runs foreign JS.
    def render(source)
      return source if format == "html"

      MarkdownDocument.render(source, title: title)
    end
end
