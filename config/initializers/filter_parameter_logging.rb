# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # Artifacto's own: the PIN in plaintext, the artifact body when it arrives as a
  # param (up to MAX_UPLOAD_BYTES per log line, PIN-locked ones included), and the
  # signed unlock tokens, which are one-letter params — anchored, since a bare :t
  # would partially match nearly every key.
  :pin, :source, :html, /\A[tk]\z/
]
