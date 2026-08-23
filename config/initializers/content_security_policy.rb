# Policy for the app host only. RawController sets its own, much stricter policy
# per artifact; the middleware leaves a response alone once the header is present.
Rails.application.configure do
  config.content_security_policy do |policy|
    x = config.x
    frame_source = "#{x.content_scheme}://*.#{x.content_host}#{x.content_port ? ":#{x.content_port}" : ''}"

    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self
    policy.img_src     :self, :data
    policy.font_src    :self, :data
    policy.connect_src :self
    policy.frame_src   frame_source
    policy.object_src  :none
    policy.base_uri    :none
    policy.form_action :self
  end

  # importmap-rails emits inline <script> tags; without a nonce the policy above
  # would block Stimulus and take the wrapper page's comment channel with it.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
