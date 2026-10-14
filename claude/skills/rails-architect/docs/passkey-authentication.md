# Passkey Authentication (WebAuthn) for Rails

Passkey-only authentication with the `webauthn-ruby` gem: no passwords, magic
links for provisioning, signed stateless challenges, Stimulus on the front end.
It keeps the session plumbing from `bin/rails generate authentication`
(`Current.session`, `start_new_session_for`, `allow_unauthenticated_access`)
and replaces the password half, which is all the generator covers.

The shape: an admin emails a `generates_token_for` magic link, the user follows it and is
logged in for long enough to register a passkey, and every login after that is
WebAuthn. Email is only an attack surface during that first 30-minute window;
after setup it plays no part in authentication.

## Contents

- [Data model](#data-model)
- [Registration must bind to Current.user](#registration-must-bind-to-currentuser)
- [Signed challenges](#signed-challenges)
- [Magic links](#magic-links)
- [Registration controller](#registration-controller)
- [Authentication controller](#authentication-controller)
- [Stimulus controller](#stimulus-controller)
- [Configuration](#configuration)
- [Rate limiting](#rate-limiting)
- [Testing with a virtual authenticator](#testing-with-a-virtual-authenticator)
- [Troubleshooting](#troubleshooting)
- [Browser capabilities worth adopting](#browser-capabilities-worth-adopting)
- [Gems and routes](#gems-and-routes)
- [References](#references)

## Data model

```ruby
create_table :credentials, id: :string do |t|
  t.string :user_id, null: false, index: true
  t.binary :credential_id, null: false, index: { unique: true }
  t.binary :public_key, null: false
  t.integer :sign_count, default: 0, null: false
  t.string :aaguid, index: true
  t.string :device_name
  t.boolean :backed_up, default: false
  t.json :transports, default: []
  t.json :metadata, default: {}
  t.datetime :last_used_at
  t.boolean :compromised, default: false
  t.timestamps

  t.foreign_key :users, on_delete: :cascade
end
```

Both `credential_id` and `public_key` arrive from the gem as base64url
*strings*, not bytes. `credential_id` gets decoded on write so lookups match
(see [Troubleshooting](#troubleshooting)); `public_key` is stored as handed
over and round-trips fine, since `verify` decodes it again. `raw_public_key` is
the accessor that returns actual bytes if you'd rather keep the column
genuinely binary.

```ruby
class User < ApplicationRecord
  has_many :credentials, dependent: :destroy

  # Opaque handle sent to the authenticator — never the primary key.
  # add_column :users, :webauthn_id, :string, null: false
  before_create { self.webauthn_id ||= WebAuthn.generate_user_id }

  # Embedding the newest credential's timestamp voids the link once a passkey
  # is registered.
  generates_token_for :passkey_setup, expires_in: 30.minutes do
    credentials.maximum(:created_at)
  end

  def passkey_registered? = credentials.exists?
end

class Credential < ApplicationRecord
  belongs_to :user

  validates :credential_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :sign_count, numericality: { greater_than_or_equal_to: 0 }

  scope :active, -> { where(compromised: false) }
  scope :by_last_used, -> { order(last_used_at: :desc) }

  def flag_as_compromised!
    update!(compromised: true)
    Rails.logger.warn "Credential #{id} flagged as compromised for user #{user_id}"
    PasskeyMailer.credential_compromised(self).deliver_later
  end

  def last_credential? = user.credentials.count == 1
end
```

With an Identity/User split (see `docs/authorization-and-roles.md`),
credentials and `webauthn_id` belong to the Identity rather than the User, so
one passkey signs into every account that identity belongs to.

## Registration must bind to Current.user

The single most important rule in this document. Both `begin` and `complete`
derive the user from `Current.user` and nothing else:

- `begin` must not do `User.find(params[:user_id] || Current.user.id)`.
- `begin` must not stash `session[:webauthn_user_id]`.
- `complete` must not read a user id from params or the session.
- `complete` must not call `start_new_session_for` — the magic link already
  signed them in.

Get any of these wrong and an authenticated attacker passes a victim's id to
`begin`, completes the ceremony with their own authenticator, and ends up logged
in as the victim with a persistent passkey on their own device. Without RBAC
that's full account takeover from any login. A completed ceremony proves only
that the attacker holds *some* authenticator; it says nothing about which
account the credential belongs to. That binding comes from the authenticated
session or it doesn't exist.

```ruby
test "begin ignores user_id param targeting another user" do
  login_as(@user)
  post webauthn_registration_begin_path, params: { user_id: @other_user.id }
  assert_response :success

  json = JSON.parse(response.body)
  assert_equal @user.email, json["user"]["name"]
  refute_equal @other_user.id, session[:webauthn_user_id]
end
```

## Signed challenges

Sign the challenge instead of storing it. The browser echoes it back inside
`clientDataJSON`, so `complete` reads it from there and checks signature,
expiry, and purpose: no session state, no table, no cleanup job. The purpose
stops a challenge minted for one ceremony from completing the other.

```ruby
# app/models/webauthn/challenge.rb
module Webauthn::Challenge
  extend self

  def generate(purpose:)
    signed = verifier.generate(SecureRandom.base64(32), expires_in: 5.minutes, purpose: purpose)
    Base64.urlsafe_encode64(signed, padding: false)
  end

  # Returns the challenge to pass to the gem's `verify`, or nil when it was
  # forged, has expired, or was minted for the other ceremony.
  def verify(webauthn_credential, purpose:)
    signed = webauthn_credential.response.client_data.challenge
    Base64.urlsafe_encode64(signed, padding: false) if verifier.verified(signed, purpose: purpose)
  rescue ArgumentError # malformed base64 in clientDataJSON
    nil
  end

  private
    def verifier = Rails.application.message_verifier("webauthn_challenge")
end
```

A signed challenge is replayable within its window. Keeping it in a cookie
session and calling `session.delete` doesn't fix that — the client can resend
the old cookie — so single use needs a server-side row. Keep the window short
and let `verify` check the sign count; synced passkeys often report a count of
0, which leaves the window as the only bound.

## Magic links

`generates_token_for` gives tamper-proof, expiring, purpose-scoped tokens with
no extra gem and no token table, and the block's value invalidates the token
when it changes — here, as soon as the user registers a passkey.

```ruby
class SessionsController < ApplicationController
  allow_unauthenticated_access only: [:new, :magic_link]

  def magic_link
    user = User.find_by_token_for!(:passkey_setup, params[:token])
    start_new_session_for user
    redirect_to new_credential_path, notice: "Welcome! Let's set up your passkey."
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to login_path, alert: "Invalid or expired setup link. Contact an administrator."
  end
end
```

Admin side — rate limited per admin/target pair, and logged for audit:

```ruby
class UsersController < ApplicationController
  before_action :require_admin, only: :send_passkey_setup_link

  rate_limit to: 3, within: 1.hour,
             by: -> { [Current.user.id, params[:id]] },
             only: :send_passkey_setup_link

  def send_passkey_setup_link
    user = User.find(params[:id])
    PasskeyMailer.setup_passkey(user, user.generate_token_for(:passkey_setup)).deliver_later
    Rails.logger.info "Admin #{Current.user.email} sent passkey setup link to #{user.email}"

    render turbo_stream: turbo_stream.replace(
      "user_#{user.id}_actions",
      partial: "users/actions", locals: { user: user, link_sent: true }
    )
  end
end
```

Until a passkey is registered the token is replayable within its 30 minutes.
For strictly single-use tokens, store a row and consume it atomically — only
one request can win `where(code: code).delete_all == 1`, whereas `find_by` then
`destroy` lets two concurrent requests both succeed.

## Registration controller

```ruby
class Webauthn::RegistrationController < ApplicationController
  # No allow_unauthenticated_access — only reachable once logged in via magic link.
  rate_limit to: 5, within: 15.minutes, by: -> { Current.user&.id }

  def begin
    options = WebAuthn::Credential.options_for_create(
      # user.id must be valid unpadded base64url — the browser decodes it.
      # Give the model a webauthn_id column from WebAuthn.generate_user_id
      # rather than passing a raw primary key; an integer id fails outright.
      user: { id: Current.user.webauthn_id, name: Current.user.email, display_name: Current.user.name },
      exclude: Current.user.credentials.pluck(:credential_id).map { |id|
        Base64.urlsafe_encode64(id, padding: false)
      },
      authenticator_selection: { resident_key: "preferred", user_verification: "preferred" }
    )

    # The signed challenge replaces the gem's random one. Nothing goes in the session.
    render json: options.as_json.merge(challenge: Webauthn::Challenge.generate(purpose: :registration))
  end

  def complete
    webauthn_credential = WebAuthn::Credential.from_create(params[:credential])
    challenge = Webauthn::Challenge.verify(webauthn_credential, purpose: :registration)

    unless challenge
      return render json: { error: "Challenge invalid or expired" }, status: :unprocessable_entity
    end

    webauthn_credential.verify(challenge)

    Current.user.credentials.create!(
      credential_id: Base64.urlsafe_decode64(webauthn_credential.id),
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      aaguid: webauthn_credential.response.aaguid,
      transports: webauthn_credential.response.transports || []
    )

    # No start_new_session_for here — that call is the takeover vector.
    render json: { success: true, redirect_url: jobs_path }
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
```

## Authentication controller

```ruby
class Webauthn::AuthenticationController < ApplicationController
  allow_unauthenticated_access

  rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip }

  def begin
    options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
    render json: options.as_json.merge(challenge: Webauthn::Challenge.generate(purpose: :authentication))
  end

  def complete
    webauthn_credential = WebAuthn::Credential.from_get(params[:credential])
    challenge = Webauthn::Challenge.verify(webauthn_credential, purpose: :authentication)

    unless challenge
      return render json: { error: "Challenge invalid or expired" }, status: :unauthorized
    end

    credential = Credential.find_by!(
      credential_id: Base64.urlsafe_decode64(params[:credential][:id])
    )

    webauthn_credential.verify(
      challenge,
      public_key: credential.public_key,
      sign_count: credential.sign_count
    )

    credential.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
    start_new_session_for credential.user
    render json: { success: true, redirect_url: jobs_path }

  # A counter that fails to advance suggests a cloned authenticator. `verify`
  # raises this itself — rescue it ahead of the generic WebAuthn::Error, or the
  # credential never gets flagged.
  rescue WebAuthn::SignCountVerificationError
    credential.flag_as_compromised!
    render json: { error: "Invalid authenticator" }, status: :unauthorized
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unauthorized
  end
end
```

Don't hand-roll the clone check. `verify` already compares the signature
counter and raises `WebAuthn::SignCountVerificationError`, and its check is
stricter than the obvious one — it also catches a new count of 0 against a
stored count above 0, which a `sign_count > 0` guard skips.

The gem verifies origin and RP ID hash for you — both must match exactly,
including scheme, port, and subdomain.

## Stimulus controller

The browser's native JSON APIs handle every ArrayBuffer ↔ base64url conversion,
so no encoding helpers are needed:

```javascript
// app/javascript/controllers/webauthn_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { beginUrl: String, completeUrl: String, mode: String }
  static targets = ["submitButton", "errorContainer"]

  async startRegistration() {
    try {
      this.setLoading(true)

      const options = await (await fetch(this.beginUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken }
      })).json()

      const credential = await navigator.credentials.create({
        publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options)
      })

      const result = await (await fetch(this.completeUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken },
        body: JSON.stringify({ credential: credential.toJSON() })
      })).json()

      if (result.success) window.location.href = result.redirect_url
    } catch (error) {
      this.handleError(error)
    } finally {
      this.setLoading(false)
    }
  }

  handleError(error) {
    const messages = {
      NotAllowedError: "Sign-in was canceled. Please try again.",
      InvalidStateError: "This passkey is already registered on this device.",
      NotSupportedError: "Passkeys are not supported on this browser."
    }
    this.errorContainerTarget.textContent = messages[error.name] ?? "An error occurred."
    this.errorContainerTarget.classList.remove("hidden")
  }

  // Optional chaining matters — the meta tag may be absent in tests.
  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
```

These `fetch` calls come from the app's own pages, so the browser sends
`Sec-Fetch-Site: same-origin`, and that header is what passes forgery
protection. Under the default `:header_only` strategy Rails never reads the
`X-CSRF-Token` header; it matters only under `:header_or_legacy_token`, for a
client that sends no `Sec-Fetch-Site`. Either way the begin/complete endpoints
stay on `ActionController::Base` with forgery protection on — a cross-site
request is rejected before a challenge is issued. See
`docs/rails-8-modern-stack.md` for the strategies.

## Configuration

```ruby
# config/initializers/webauthn.rb
WebAuthn.configure do |config|
  config.allowed_origins = if Rails.env.test?
    TestOriginChecker.new                # see testing section
  elsif Rails.env.production?
    [ ENV.fetch("WEBAUTHN_ORIGIN") ]     # protocol + host + port
  else
    [ "http://localhost:3000" ]
  end

  config.rp_id = Rails.env.production? ? ENV.fetch("WEBAUTHN_RP_ID") : "localhost"
  config.rp_name = ENV.fetch("WEBAUTHN_RP_NAME", "Your App Name")

  config.encoding = :base64url  # required by the native browser JSON APIs
  config.credential_options_timeout = 60_000
  config.algorithms = ["ES256", "RS256"]
end
```

`rp_id` is a bare domain — no scheme, no port.

Optionally add the `fido_metadata` gem to turn AAGUIDs into real device names
("YubiKey 5 NFC" rather than "Security Key"). It needs an explicit cache
backend or `Store` raises at runtime, and it caches until the MDS blob's own
`nextUpdate` — typically weeks, not a fixed day:

```ruby
# config/initializers/fido_metadata.rb
FidoMetadata.configure { |config| config.cache_backend = Rails.cache }
```

Resolve it off the request. `fetch_statement` returns nil for an unknown
AAGUID rather than raising, so guard on the return value:

```ruby
class FetchAuthenticatorMetadataJob < ApplicationJob
  def perform(credential_id)
    credential = Credential.find(credential_id)
    return if credential.aaguid.blank?

    statement = FidoMetadata::Store.new.fetch_statement(aaguid: credential.aaguid)

    if statement
      credential.update!(device_name: statement.description,
                         metadata: { description: statement.description })
    else
      credential.update!(device_name: "Unknown Authenticator")
    end
  end
end
```

Certification status isn't on the statement — it lives on the entry's
`status_reports`. And under the default `attestation: none`, `aaguid` comes
back zeroed, so this job is a no-op for most registrations.

## Rate limiting

Rails' own `ActionController::RateLimiting` is enough; rack-attack isn't needed.

```
def rate_limit(to:, within:, by: -> { request.remote_ip },
               with: -> { raise TooManyRequests },
               store: cache_store, name: nil, scope: nil, **options)
```

Exceeding the limit raises `ActionController::TooManyRequests`. Rails' exception
wrapper already maps it to a 429, so no `rescue_from` is needed for the status
code alone. It's a bare exception class — there is no
`retry_after` on it and no message payload, so a custom response has to come
from `with:` rather than from reading the exception:

```ruby
rate_limit to: 10, within: 15.minutes,
           by: -> { request.remote_ip },
           with: -> { render json: { error: "Too many attempts." },
                             status: :too_many_requests }
```

The backing store is `config.action_controller.cache_store`, or `store:` per
call — there is no `rate_limiting_cache_store` setting.

## Testing with a virtual authenticator

Selenium's virtual authenticator runs the whole ceremony in headless Chrome, so
passkey flows are testable in CI without hardware. Three settings have to line
up or nothing works:

**Hostname.** The WebAuthn spec rejects IP addresses as RP ID, and Capybara
defaults to `127.0.0.1`, which yields `SecurityError: This is an invalid
domain`. `localhost` is specified as a special case.

```ruby
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome

  setup { Capybara.server_host = "localhost" }
end
```

**Random ports.** Capybara picks a port per run, so `allowed_origins` can't be a
fixed array. The gem accepts anything responding to `include?`:

```ruby
class TestOriginChecker
  def include?(origin)
    uri = URI.parse(origin)
    (uri.host == "localhost" || uri.host == "127.0.0.1") && uri.scheme == "http"
  rescue URI::InvalidURIError
    false
  end
end
```

**Encoding.** `config.encoding = :base64url`. With plain `:base64` the native
browser APIs raise `EncodingError: 'challenge' contains invalid base64url data`.

Helpers:

```ruby
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  def setup_virtual_authenticator(options = {})
    defaults = Selenium::WebDriver::VirtualAuthenticatorOptions.new(
      protocol: :ctap2,        # FIDO2
      transport: :internal,    # platform authenticator
      resident_key: true,      # required for passkeys
      user_verified: true,     # skip the biometric prompt
      user_verification: true
    )
    options.each { |key, value| defaults.send("#{key}=", value) }
    @virtual_authenticator = page.driver.browser.add_virtual_authenticator(defaults)
  end

  def remove_virtual_authenticator
    @virtual_authenticator&.remove!
    @virtual_authenticator = nil
  rescue Selenium::WebDriver::Error::InvalidArgumentError
    @virtual_authenticator = nil
  end

  def register_passkey_via_ui(user)
    visit magic_link_path(user.generate_token_for(:passkey_setup))
    assert_current_path new_credential_path
    click_button "Create passkey"
    assert_current_path jobs_path, wait: 10
    user.reload.credentials.last
  end
end
```

```ruby
class PasskeyAuthenticationTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @user.credentials.destroy_all  # fixture credentials have no matching private key
    setup_virtual_authenticator    # before any visit
  end

  teardown { remove_virtual_authenticator }  # else credentials leak between tests

  test "user registers passkey via magic link" do
    visit magic_link_path(@user.generate_token_for(:passkey_setup))
    click_button "Create passkey"

    assert_current_path jobs_path, wait: 10  # ceremonies are async; short waits flake
    assert @user.reload.passkey_registered?
  end

  test "user authenticates with passkey" do
    register_passkey_via_ui(@user)
    find("el-dropdown button").click
    click_on "Sign out"

    visit login_path
    click_button "Sign in with passkey"
    assert_current_path jobs_path, wait: 10
  end

  test "expired magic link is rejected" do
    token = @user.generate_token_for(:passkey_setup)
    travel 31.minutes                  # mint first, then advance — not travel { mint }
    visit magic_link_path(token)
    assert_text "Invalid or expired setup link"
  end
end
```

## Troubleshooting

**`ActiveRecord::RecordNotFound` on login after successful registration.** The
credential ID was stored as a base64url *string* while lookup decodes to binary.
Decode on the way in: `Base64.urlsafe_decode64(webauthn_credential.id)`.

**`'challenge' contains invalid base64url data`.** `config.encoding` is
`:base64`; it must be `:base64url`.

**`'excludeCredentials' contains PublicKeyCredentialDescriptorJSON with invalid
base64url data in 'id'`.** The exclusion list takes encoded strings, not the raw
binary column — map it through `Base64.urlsafe_encode64(id, padding: false)`.
The browser decodes unpadded, so `padding: false` is required, not cosmetic.

**`SecurityError: This is an invalid domain`.** RP ID is an IP or doesn't match
the origin host. Set `Capybara.server_host = "localhost"` and `rp_id:
"localhost"` in test.

**Virtual authenticator never intercepts.** It was created after the page was
visited, or is missing `resident_key: true` / `transport: :internal`.

## Browser capabilities worth adopting

Support varies, so feature-detect rather than assume.

**Conditional UI** puts passkeys in the autofill dropdown, removing the need for
a dedicated button. Requires `autocomplete="username webauthn"` on the input:

```javascript
if (await PublicKeyCredential.isConditionalMediationAvailable()) {
  const credential = await navigator.credentials.get({
    publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(options),
    mediation: "conditional"
  })
}
```

**Hints** steer the browser's picker — `client-device`, `security-key`, or
`hybrid` (cross-device via QR). Merge them in server-side alongside the
challenge:

```ruby
render json: options.as_json.merge(
  challenge: Webauthn::Challenge.generate(purpose: :authentication),
  hints: ["client-device", "hybrid"]
)
```

**Signal API** keeps the authenticator's passkey list in sync with the server,
so deleted credentials stop being offered:

```javascript
await PublicKeyCredential.signalUnknownCredential?.({ rpId, credentialId })
await PublicKeyCredential.signalCurrentUserDetails?.({ rpId, userId, name, displayName })
await PublicKeyCredential.signalAllAcceptedCredentials?.({ rpId, userId, allAcceptedCredentialIds })
```

**Related origin requests** share passkeys across domains (`example.com` and
`example.co.uk`) via a `.well-known/webauthn` file served over HTTPS from the
`rp_id` domain as `application/json`, with a top-level `origins` array. The RP
ID domain itself isn't listed — its own origins pass the ordinary check and
never consume budget. Clients need only support five registrable origin
*labels*, and the limit counts labels rather than entries, so many origins
across few suffixes are fine.

## Gems and routes

```ruby
gem "webauthn", "~> 3.4"
gem "selenium-webdriver", "~> 4.35"  # virtual authenticator support
gem "fido_metadata"                  # optional, device names
```

```ruby
namespace :webauthn do
  namespace :registration do
    post :begin
    post :complete
  end
  namespace :authentication do
    post :begin
    post :complete
  end
end

resources :credentials, only: [:index, :new, :destroy]

get "/login", to: "sessions#new"
get "/login/:token", to: "sessions#magic_link", as: :magic_link
delete "/logout", to: "sessions#destroy"
```

## References

- [W3C WebAuthn Level 3](https://www.w3.org/TR/webauthn-3/)
- [webauthn-ruby](https://github.com/cedarcode/webauthn-ruby)
- [Selenium virtual authenticator](https://www.selenium.dev/documentation/webdriver/interactions/virtual_authenticator/)
- [MDN Web Authentication API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API)
