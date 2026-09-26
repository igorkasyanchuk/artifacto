# Policy for the app host only. RawController sets its own, much stricter policy
# per artifact; the middleware leaves a response alone once the header is present.
Rails.application.configure do
  config.content_security_policy do |policy|
    x = config.x
    frame_source =
      if x.content_host
        "#{x.content_scheme}://*.#{x.content_host}#{x.content_port ? ":#{x.content_port}" : ''}"
      else
        :self
      end

    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self
    # The comment overlay positions pins and the thread panel by writing to
    # element.style, which style-src governs. Only the attribute form is opened,
    # not <style> elements — and this origin renders no untrusted markup: comment
    # bodies are written with textContent, never innerHTML.
    policy.style_src_attr :unsafe_inline
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
  # style-src too: Turbo injects its progress bar's <style> with the page nonce,
  # and without one every Turbo page logged a CSP violation.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
