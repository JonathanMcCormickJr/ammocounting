# Be sure to restart your server when you modify this file.

# Content security policy: scripts and styles only from this origin (importmap
# and Turbo's progress-bar style carry a per-request nonce); no plugins, no
# framing, no foreign form targets. The app has no inline scripts or styles.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.font_src        :self
    policy.img_src         :self, :data
    policy.object_src      :none
    policy.script_src      :self
    policy.style_src       :self
    policy.connect_src     :self
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :none
  end

  # A fresh random nonce per request (does not depend on a session existing).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
  config.content_security_policy_nonce_auto = true
end
