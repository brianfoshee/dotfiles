# Passkey Authentication (WebAuthn) for Rails

Passkey-only authentication with the `webauthn-ruby` gem: no passwords, magic
links for provisioning, signed stateless challenges, Stimulus on the front end.
It keeps the session plumbing from `bin/rails generate authentication`
(`Current.session`, `start_new_session_for`, `allow_unauthenticated_access`)
and replaces the password half, which is all the generator covers.

The shape: an admin emails a `generates_token_for` magic link, the user follows
it and is logged in for long enough to register a passkey, and every login
after that is WebAuthn. Email is only an attack surface during that first
30-minute window.

## Contents

- [Data model](#data-model)
- [Registration must bind to Current.user](#registration-must-bind-to-currentuser)
- [Signed challenges](#signed-challenges)
- [Magic links](#magic-links)
- [Ceremony details](#ceremony-details)
- [Stimulus controller](#stimulus-controller)
- [Configuration](#configuration)
- [Testing with a virtual authenticator](#testing-with-a-virtual-authenticator)
- [Troubleshooting](#troubleshooting)
- [Browser capabilities worth adopting](#browser-capabilities-worth-adopting)
- [References](#references)

## Data model

A `credentials` table with `credential_id` (binary, unique), `public_key`,
`sign_count`, `aaguid`, `device_name`, `backed_up`, `transports`,
`last_used_at` and `compromised`. Both `credential_id` and `public_key` arrive
from the gem as base64url *strings*, not bytes: decode `credential_id` on write
so lookups match (see [Troubleshooting](#troubleshooting)); `public_key` is
stored as handed over and round-trips, since `verify` decodes it again.

```ruby
class User < ApplicationRecord
  has_many :credentials, dependent: :destroy

  # Opaque handle sent to the authenticator — never the primary key.
  before_create { self.webauthn_id ||= WebAuthn.generate_user_id }

  # Embedding the newest credential's timestamp voids the link once a passkey
  # is registered.
  generates_token_for :passkey_setup, expires_in: 30.minutes do
    credentials.maximum(:created_at)
  end
end
```

With an Identity/User split (see `docs/authorization-and-roles.md`),
credentials and `webauthn_id` belong to the Identity rather than the User, so
one passkey signs into every account that identity belongs to.

## Registration must bind to Current.user

Both `begin` and `complete` derive the user from `Current.user` and nothing
else:

- `begin` must not do `User.find(params[:user_id] || Current.user.id)`.
- `begin` must not stash `session[:webauthn_user_id]`.
- `complete` must not read a user id from params or the session.
- `complete` must not call `start_new_session_for` — the magic link already
  signed them in.

Get any of these wrong and an authenticated attacker passes a victim's id to
`begin`, completes the ceremony with their own authenticator, and ends up logged
in as the victim with a persistent passkey on their own device. A completed
ceremony proves only that the attacker holds *some* authenticator; the binding
to an account comes from the authenticated session or it doesn't exist. Test it:

```ruby
test "begin ignores user_id param targeting another user" do
  login_as(@user)
  post webauthn_registration_begin_path, params: { user_id: @other_user.id }

  assert_equal @user.email, JSON.parse(response.body)["user"]["name"]
end
```

## Signed challenges

Sign the challenge instead of storing it. The browser echoes it back inside
`clientDataJSON`, so `complete` reads it from there and checks signature,
expiry and purpose: no session state, no table, no cleanup job. The purpose
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
no table, and the block's value invalidates the token when it changes — here,
as soon as the user registers a passkey. `User.find_by_token_for!` raises
`ActiveSupport::MessageVerifier::InvalidSignature` or `RecordNotFound`; answer
both the same way. Rate limit the admin's send action per admin/target pair
(`by: -> { [Current.user.id, params[:id]] }`) and log it for audit.

Until a passkey is registered the token is replayable within its 30 minutes.
For strictly single-use tokens, store a row and consume it atomically — only
one request can win `where(code: code).delete_all == 1`, whereas `find_by` then
`destroy` lets two concurrent requests both succeed.

## Ceremony details

The controllers follow the gem's README. What it doesn't say:

- `options_for_create` takes `user: { id: Current.user.webauthn_id, ... }`. The
  id must be valid unpadded base64url because the browser decodes it; a raw
  integer primary key fails outright.
- `exclude:` takes encoded strings, not the binary column:
  `credentials.pluck(:credential_id).map { |id| Base64.urlsafe_encode64(id, padding: false) }`.
  `padding: false` is required, not cosmetic.
- Replace the gem's random challenge with the signed one:
  `render json: options.as_json.merge(challenge: Webauthn::Challenge.generate(purpose: :registration))`.
- Store `credential_id: Base64.urlsafe_decode64(webauthn_credential.id)`, and
  look it up the same way on authentication.
- Don't hand-roll the clone check. `verify` compares the signature counter and
  raises `WebAuthn::SignCountVerificationError`; its check also catches a new
  count of 0 against a stored count above 0, which a `sign_count > 0` guard
  skips. Rescue it *ahead of* the generic `WebAuthn::Error`, or the credential
  never gets flagged compromised.
- Rate limit `begin`/`complete`: registration by `Current.user&.id`,
  authentication by `request.remote_ip`. Rails' `rate_limit` is enough;
  rack-attack isn't needed (gotchas in SKILL.md).

## Stimulus controller

The browser's native JSON APIs handle every ArrayBuffer ↔ base64url conversion,
so no encoding helpers are needed:

```javascript
const options = await (await fetch(this.beginUrlValue, { method: "POST", headers })).json()
const credential = await navigator.credentials.create({
  publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options)
})
await fetch(this.completeUrlValue, {
  method: "POST", headers, body: JSON.stringify({ credential: credential.toJSON() })
})
```

Map `NotAllowedError` (cancelled), `InvalidStateError` (already registered on
this device) and `NotSupportedError` to user-facing messages. Read the CSRF meta
tag with optional chaining — it may be absent in tests.

These `fetch` calls come from the app's own pages, so the browser sends
`Sec-Fetch-Site: same-origin`, which is what passes forgery protection under
the default `:header_only` strategy; the `X-CSRF-Token` header matters only
under `:header_or_legacy_token`. Keep the endpoints on `ActionController::Base`
with forgery protection on, so a cross-site request is rejected before a
challenge is issued.

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

  config.rp_id = Rails.env.production? ? ENV.fetch("WEBAUTHN_RP_ID") : "localhost"  # bare domain
  config.encoding = :base64url  # required by the native browser JSON APIs
end
```

The optional `fido_metadata` gem turns AAGUIDs into device names ("YubiKey 5
NFC"). It needs `FidoMetadata.configure { |c| c.cache_backend = Rails.cache }`
or `Store` raises at runtime, and it caches until the MDS blob's own
`nextUpdate` — weeks, not a fixed day. Resolve off the request in a job;
`fetch_statement` returns nil for an unknown AAGUID rather than raising.
Certification status lives on the entry's `status_reports`, not the statement.
Under the default `attestation: none`, `aaguid` comes back zeroed, so the job
is a no-op for most registrations.

## Testing with a virtual authenticator

Selenium's virtual authenticator runs the whole ceremony in headless Chrome.
Three settings have to line up or nothing works:

**Hostname.** The WebAuthn spec rejects IP addresses as RP ID, and Capybara
defaults to `127.0.0.1`, which yields `SecurityError: This is an invalid
domain`. Set `Capybara.server_host = "localhost"` in the system test case.

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
end
```

Create the authenticator before any `visit`, remove it in `teardown` or
credentials leak between tests, and `destroy_all` fixture credentials first —
they have no matching private key. Ceremonies are async, so assert with
`wait: 10`; short waits flake. For an expiry test, mint the token first and
then `travel 31.minutes` — not `travel { mint }`.

## Troubleshooting

**`ActiveRecord::RecordNotFound` on login after successful registration.** The
credential ID was stored as a base64url *string* while lookup decodes to binary.
Decode on the way in: `Base64.urlsafe_decode64(webauthn_credential.id)`.

**`'challenge' contains invalid base64url data`.** `config.encoding` is
`:base64`; it must be `:base64url`.

**`'excludeCredentials' contains PublicKeyCredentialDescriptorJSON with invalid
base64url data in 'id'`.** The exclusion list takes encoded strings, not the raw
binary column — map it through `Base64.urlsafe_encode64(id, padding: false)`.

**`SecurityError: This is an invalid domain`.** RP ID is an IP or doesn't match
the origin host. Set `Capybara.server_host = "localhost"` and `rp_id:
"localhost"` in test.

**Virtual authenticator never intercepts.** It was created after the page was
visited, or is missing `resident_key: true` / `transport: :internal`.

## Browser capabilities worth adopting

Support varies, so feature-detect rather than assume.

**Conditional UI** puts passkeys in the autofill dropdown, removing the need for
a dedicated button. Requires `autocomplete="username webauthn"` on the input and
`mediation: "conditional"` after
`PublicKeyCredential.isConditionalMediationAvailable()`.

**Hints** steer the browser's picker — `client-device`, `security-key`, or
`hybrid` (cross-device via QR). Merge `hints:` into the options JSON
server-side alongside the challenge.

**Signal API** keeps the authenticator's passkey list in sync with the server,
so deleted credentials stop being offered: `signalUnknownCredential`,
`signalCurrentUserDetails`, `signalAllAcceptedCredentials` on
`PublicKeyCredential`, all optional-chained.

**Related origin requests** share passkeys across domains (`example.com` and
`example.co.uk`) via a `.well-known/webauthn` file served over HTTPS from the
`rp_id` domain as `application/json`, with a top-level `origins` array. The RP
ID domain itself isn't listed. Clients need only support five registrable
origin *labels*, and the limit counts labels rather than entries.

## References

- [W3C WebAuthn Level 3](https://www.w3.org/TR/webauthn-3/)
- [webauthn-ruby](https://github.com/cedarcode/webauthn-ruby)
- [Selenium virtual authenticator](https://www.selenium.dev/documentation/webdriver/interactions/virtual_authenticator/)
