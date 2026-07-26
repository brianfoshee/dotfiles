# Passkey Authentication (WebAuthn) for Rails

Passkey-only authentication with the `webauthn-ruby` gem: no passwords, magic
links for provisioning, challenges in the session, Stimulus on the front end.
Rails' built-in `bin/rails generate authentication` covers email/password only,
so this is all hand-rolled.

The shape: an admin emails a `signed_id` magic link, the user follows it and is
logged in for long enough to register a passkey, and every login after that is
WebAuthn. Email is only an attack surface during that first 30-minute window;
after setup it plays no part in authentication.

## Contents

- [Data model](#data-model)
- [Registration must bind to current_user](#registration-must-bind-to-current_user)
- [Session-based challenges](#session-based-challenges)
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

`credential_id` and `public_key` are binary because that's what the gem hands
back; storing them as strings breaks lookup (see [Troubleshooting](#troubleshooting)).

```ruby
class User < ApplicationRecord
  has_many :credentials, dependent: :destroy

  def passkey_registered? = credentials.exists?

  def generate_magic_link_token
    signed_id(expires_in: 30.minutes, purpose: :passkey_setup)
  end
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

## Registration must bind to current_user

The single most important rule in this document. Both `begin` and `complete`
derive the user from `current_user` and nothing else:

- `begin` must not do `User.find(params[:user_id] || current_user.id)`.
- `begin` must not stash `session[:webauthn_user_id]`.
- `complete` must not read a user id from params or the session.
- `complete` must not call `login(user)` — the magic link already logged them in.

Get any of these wrong and an authenticated attacker passes a victim's id to
`begin`, completes the ceremony with their own authenticator, and ends up logged
in as the victim with a persistent passkey on their own device. Without RBAC
that's full account takeover from any login. A completed ceremony proves only
that the attacker holds *some* authenticator; it says nothing about which
account the credential belongs to. That binding comes from the server-side
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

## Session-based challenges

Challenges live in the session rather than a table: no cleanup job, expiry comes
free, the challenge is bound to one browser, and `session.delete` enforces
single use. Rails encrypts session data already.

```ruby
# Store
session[:webauthn_challenge] = options.challenge
session[:webauthn_challenge_created_at] = Time.current

# Retrieve — single use
challenge = session.delete(:webauthn_challenge)
created_at = session.delete(:webauthn_challenge_created_at)

if Time.current - created_at > 10.minutes
  return render json: { error: "Challenge expired" }, status: :unprocessable_entity
end
```

This needs a database-backed session store — a ~170 byte challenge doesn't
belong in a cookie:

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :active_record_store,
  key: "_your_app_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax,
  expire_after: 1.week
```

Generate the table with `bin/rails generate active_record:session_migration`.

## Magic links

`signed_id` gives tamper-proof, expiring, purpose-scoped tokens with no extra
gem and no token table, and it works with UUID primary keys.

```ruby
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :magic_link]

  def magic_link
    user = User.find_signed!(params[:token], purpose: :passkey_setup)
    login(user)
    redirect_to new_credential_path, notice: "Welcome! Let's set up your passkey."
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to login_path, alert: "Invalid or expired setup link. Contact an administrator."
  end
end
```

Admin side — rate limited per admin/target pair, and logged for audit:

```ruby
class UsersController < ApplicationController
  before_action :require_admin, only: :send_passkey_setup_link

  rate_limit to: 3, within: 1.hour,
             by: -> { [current_user.id, params[:id]] },
             only: :send_passkey_setup_link

  def send_passkey_setup_link
    user = User.find(params[:id])
    PasskeyMailer.setup_passkey(user, user.generate_magic_link_token).deliver_later
    Rails.logger.info "Admin #{current_user.email} sent passkey setup link to #{user.email}"

    render turbo_stream: turbo_stream.replace(
      "user_#{user.id}_actions",
      partial: "users/actions", locals: { user: user, link_sent: true }
    )
  end
end
```

The token is replayable within its 30-minute window. To make it strictly
single-use, track consumption:

```ruby
def verify_magic_link!
  raise "Magic link already used" if magic_link_used_at&.after?(30.minutes.ago)
  update_column(:magic_link_used_at, Time.current)
end
```

## Registration controller

```ruby
class Webauthn::RegistrationController < ApplicationController
  # No skip_before_action — only reachable once logged in via magic link.
  rate_limit to: 5, within: 15.minutes, by: -> { current_user&.id }

  def begin
    user = current_user

    options = WebAuthn::Credential.options_for_create(
      user: { id: user.id, name: user.email, display_name: user.name },
      exclude: user.credentials.pluck(:credential_id).map { |id|
        Base64.urlsafe_encode64(id, padding: false)
      },
      authenticator_selection: { resident_key: "preferred", user_verification: "preferred" }
    )

    # Challenge only — never a user id.
    session[:webauthn_challenge] = options.challenge
    session[:webauthn_challenge_created_at] = Time.current

    render json: options
  end

  def complete
    challenge = session.delete(:webauthn_challenge)
    created_at = session.delete(:webauthn_challenge_created_at)

    unless challenge && created_at
      return render json: { error: "No active registration challenge" },
                    status: :unprocessable_entity
    end

    if Time.current - created_at > 10.minutes
      return render json: { error: "Challenge expired" }, status: :unprocessable_entity
    end

    user = current_user
    webauthn_credential = WebAuthn::Credential.from_create(params[:credential])
    webauthn_credential.verify(challenge)

    user.credentials.create!(
      credential_id: Base64.urlsafe_decode64(webauthn_credential.id),
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      aaguid: webauthn_credential.response.aaguid,
      transports: webauthn_credential.response.transports || []
    )

    # No login() here — that call is the takeover vector.
    render json: { success: true, redirect_url: jobs_path }
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
```

## Authentication controller

```ruby
class Webauthn::AuthenticationController < ApplicationController
  skip_before_action :require_authentication

  rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip }

  def begin
    options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
    session[:webauthn_challenge] = options.challenge
    session[:webauthn_challenge_created_at] = Time.current
    render json: options
  end

  def complete
    challenge = session.delete(:webauthn_challenge)
    created_at = session.delete(:webauthn_challenge_created_at)

    unless challenge && created_at
      return render json: { error: "No active challenge" }, status: :unauthorized
    end

    credential = Credential.find_by!(
      credential_id: Base64.urlsafe_decode64(params[:credential][:id])
    )
    webauthn_credential = WebAuthn::Credential.from_get(params[:credential])

    webauthn_credential.verify(
      challenge,
      public_key: credential.public_key,
      sign_count: credential.sign_count
    )

    # A counter that fails to advance suggests a cloned authenticator.
    if webauthn_credential.sign_count > 0 &&
       webauthn_credential.sign_count <= credential.sign_count
      credential.flag_as_compromised!
      return render json: { error: "Invalid authenticator" }, status: :unauthorized
    end

    credential.update!(sign_count: webauthn_credential.sign_count, last_used_at: Time.current)
    login(credential.user)
    render json: { success: true, redirect_url: jobs_path }
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unauthorized
  end
end
```

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
("YubiKey 5 NFC" rather than "Security Key"). Point it at `Rails.cache`; it
fetches from FIDO MDS on first sight of an AAGUID and caches for 24 hours.
Resolve it off the request:

```ruby
class FetchAuthenticatorMetadataJob < ApplicationJob
  def perform(credential_id)
    credential = Credential.find(credential_id)
    return if credential.aaguid.blank?

    statement = FidoMetadata::Store.new.fetch_statement(aaguid: credential.aaguid)
    credential.update!(
      device_name: statement.description,
      metadata: { description: statement.description,
                  is_fido_certified: statement.fido_certified? }
    )
  rescue KeyError
    credential.update!(device_name: "Unknown Authenticator")
  end
end
```

## Rate limiting

Rails' own `ActionController::RateLimiting` is enough; rack-attack isn't needed.

```ruby
# config/environments/production.rb
config.action_controller.rate_limiting_cache_store = :solid_cache_store

# app/controllers/application_controller.rb
rescue_from ActionController::RateLimitExceeded do |exception|
  respond_to do |format|
    format.json do
      render json: { error: "Rate limit exceeded.", retry_after: exception.retry_after },
             status: :too_many_requests
    end
    format.html do
      flash[:alert] = "Too many attempts. Try again in #{exception.retry_after} seconds."
      redirect_back fallback_location: root_path
    end
  end
end
```

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
    visit magic_link_path(user.generate_magic_link_token)
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
    visit magic_link_path(@user.generate_magic_link_token)
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
    travel(31.minutes) { @token = @user.generate_magic_link_token }
    visit magic_link_path(@token)
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

**`excludeCredentials contains invalid base64url data`.** The exclusion list
takes encoded strings, not the raw binary column — map it through
`Base64.urlsafe_encode64(id, padding: false)`.

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
`hybrid` (cross-device via QR). Merge them into the options hash server-side:

```ruby
options_hash = JSON.parse(options.to_json)
options_hash["hints"] = ["client-device", "hybrid"]
render json: options_hash
```

**Signal API** keeps the authenticator's passkey list in sync with the server,
so deleted credentials stop being offered:

```javascript
await PublicKeyCredential.signalUnknownCredential?.({ rpId, credentialId })
await PublicKeyCredential.signalCurrentUserDetails?.({ rpId, userId, name, displayName })
await PublicKeyCredential.signalAllAcceptedCredentials?.({ rpId, userId, allAcceptedCredentialIds })
```

**Related origin requests** share passkeys across domains (`example.com` and
`example.co.uk`) via a `.well-known/webauthn` file served from the `rp_id`
domain, listing the other origins. The RP ID domain itself isn't listed.

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
