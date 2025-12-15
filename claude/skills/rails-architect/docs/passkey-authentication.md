# Passkey Authentication (WebAuthn) for Rails

Production-ready passkey authentication implementation pattern based on real-world Rails 8.1 application.

## Overview

This guide shows how to implement passkey-only authentication in Rails applications using WebAuthn, without passwords or traditional authentication systems.

## Key Architectural Decisions

1. **Admin-Controlled Provisioning** - Users receive passkey setup links from admins (no self-service registration)
2. **Passkey-Only** - No passwords, pure WebAuthn authentication
3. **Session-Based Challenges** - Store WebAuthn challenges in Rails session (not database)
4. **Rails Built-in Rate Limiting** - Use `ActionController::RateLimiting` (not rack-attack)
5. **Native JSON APIs** - Use browser's `toJSON()`/`parseJSON()` methods
6. **Stimulus Controllers** - JavaScript organized via Hotwire Stimulus
7. **Virtual Authenticator Testing** - Selenium's WebAuthn virtual authenticator for system tests

## Why This Pattern?

**Benefits:**
- ✅ No password storage or management
- ✅ Phishing-resistant authentication
- ✅ Better UX (fingerprint/face authentication)
- ✅ Simpler implementation (session-based challenges)
- ✅ No additional database tables for challenges

**Trade-offs:**
- ⚠️ Requires JavaScript (progressive enhancement not possible)
- ⚠️ Requires HTTPS in production
- ⚠️ Browser support required (all modern browsers support WebAuthn)

## Security Superiority: Magic Links + Passkeys vs Traditional Authentication

### The Security Hierarchy (Best to Worst)

```
1. 🥇 Magic Links + Passkeys (This Pattern)
   └─ NIST AAL2/AAL3 compliant, phishing-resistant by design

2. 🥈 Passwords + Hardware 2FA (YubiKey)
   └─ Phishing-resistant if hardware-based, but passwords still vulnerable

3. 🥉 Passwords + Authenticator App (TOTP)
   └─ Vulnerable to phishing, credential theft, password weaknesses

4. ⚠️  Passwords + Email Codes
   └─ Email interception, password weaknesses, account takeover

5. 🚫 Passwords + SMS 2FA
   └─ SIM swapping, SMS interception, outdated (2025 standards)

6. 🚫 Passwords Only
   └─ Vulnerable to all password attacks (phishing, reuse, breaches)
```

### Why Magic Links + Passkeys Are Superior

#### 1. Phishing-Resistant by Design (FIDO2/WebAuthn)

**Passkeys:**
- ✅ **Cryptographically bound to domain** - A passkey for `example.com` cannot be used on `evil-example.com`
- ✅ **No transmittable secrets** - Only cryptographic proof is exchanged, immune to replay attacks
- ✅ **Origin validation** - Browser enforces that authentication only works on legitimate domain
- ✅ **NIST SP 800-63-4 compliant** - Synced passkeys are AAL2, device-bound are AAL3

**Traditional passwords/2FA:**
- ❌ **Phishable** - Users can be tricked into entering credentials on fake sites
- ❌ **Replayable** - Stolen credentials work on any site
- ❌ **Social engineering vulnerable** - Attackers can convince users to share OTP codes

**Real-world impact:**
- 87% of hacking-related breaches are caused by weak or stolen passwords
- 967% rise in credential phishing since 2022
- Password breaches expose credentials that work across multiple sites

#### 2. Magic Links Eliminate Password Vulnerabilities

**Magic links remove:**
- ✅ **Brute-force attacks** - No password to guess
- ✅ **Dictionary attacks** - No password to crack
- ✅ **Password reuse** - Each link is unique and temporary
- ✅ **Weak passwords** - No user-chosen passwords
- ✅ **Credential stuffing** - No credentials to stuff
- ✅ **Password database breaches** - No passwords stored

**Compared to passwords:**
- ❌ Passwords are reused across sites (81% of breaches involve weak/stolen passwords)
- ❌ Passwords can be guessed, cracked, or stolen
- ❌ Password databases are prime targets for attackers
- ❌ Users choose weak passwords despite policies

#### 3. Superior to SMS 2FA (Deprecated in 2025)

**Why SMS 2FA is insecure:**
- 🚫 **SIM swapping** - Attacker convinces carrier to transfer number to their SIM
- 🚫 **SMS interception** - Unencrypted SMS can be intercepted
- 🚫 **SS7 vulnerabilities** - Telecom protocol allows message interception
- 🚫 **Phishable** - Users can be tricked into sharing codes
- 🚫 **Man-in-the-middle** - Real-time phishing can intercept and use codes

**NIST 2025 guidance:**
> SMS is no longer recommended for authentication. Organizations must adopt phishing-resistant methods like FIDO2 and passkeys.

**Passkeys instead:**
- ✅ Not interceptable or transferable
- ✅ No phone number dependency
- ✅ Works offline (device-based verification)
- ✅ Phishing-resistant by cryptographic design

#### 4. Superior to Email OTP Codes

**Why email codes are insecure:**
- ❌ **Email account takeover** - If email is compromised, all accounts are compromised
- ❌ **Email interception** - Unencrypted email can be intercepted
- ❌ **Phishable** - Users can be tricked into sharing codes
- ❌ **Corporate scanning** - Email scanners may pre-click/consume codes
- ❌ **Forwarding rules** - Attackers can set up forwarding rules
- ❌ **Persistent access** - Codes remain in inbox, extending attack window

**Magic links improve on email codes:**
- ✅ **Time-limited** - Expire after 30 minutes (vs codes that may not expire)
- ✅ **Purpose-scoped** - Can only be used for passkey setup (vs generic OTP)
- ✅ **Cryptographically signed** - Tamper-proof (vs plain text codes)
- ✅ **One-way transition** - Used to establish passkeys, not ongoing authentication

**Critical difference:**
- Magic links are a **setup mechanism** for passkeys, not the primary authentication
- Once passkey is set up, user never relies on email again for authentication
- Traditional email OTP is used for **every login**, creating ongoing vulnerability

#### 5. Built-in Multi-Factor Authentication

**Passkeys are 2FA by default:**
- ✅ **Something you have** - The device with the private key
- ✅ **Something you are** - Biometric verification (Touch ID/Face ID)
- ✅ **Bound to device** - Cannot be copied or transmitted

**Traditional passwords:**
- ❌ Only 1FA (something you know)
- ❌ Requires additional 2FA setup
- ❌ 2FA can be bypassed, disabled, or social engineered

#### 6. Cannot Be Stolen, Guessed, or Sold

**Passkeys:**
- ✅ **Private key never leaves device** - Impossible to steal remotely
- ✅ **No dark web marketplace** - Nothing to sell or buy
- ✅ **No database to breach** - Public keys are useless without private key
- ✅ **Biometric-protected** - Requires physical device access + biometric

**Passwords:**
- ❌ Stolen in breaches and sold on dark web
- ❌ Reused passwords work across sites
- ❌ Can be guessed or cracked offline
- ❌ No physical device required

### Security Comparison Table

| Attack Vector | Passwords + SMS | Passwords + Email OTP | Passwords + TOTP App | Magic Links + Passkeys |
|---------------|:---------------:|:---------------------:|:--------------------:|:---------------------:|
| **Phishing** | ❌ Vulnerable | ❌ Vulnerable | ❌ Vulnerable | ✅ **Immune** |
| **Credential Stuffing** | ❌ Vulnerable | ❌ Vulnerable | ❌ Vulnerable | ✅ **Immune** |
| **Password Breaches** | ❌ Vulnerable | ❌ Vulnerable | ❌ Vulnerable | ✅ **Immune** |
| **SIM Swapping** | ❌ Vulnerable | N/A | N/A | ✅ **Immune** |
| **Email Compromise** | N/A | ❌ Critical | N/A | ⚠️ Setup only |
| **Man-in-the-Middle** | ❌ Vulnerable | ❌ Vulnerable | ⚠️ Partial | ✅ **Immune** |
| **Social Engineering** | ❌ Vulnerable | ❌ Vulnerable | ❌ Vulnerable | ✅ **Resistant** |
| **Brute Force** | ❌ Vulnerable | ❌ Vulnerable | ❌ Vulnerable | ✅ **Immune** |
| **Replay Attacks** | ❌ Vulnerable | ⚠️ Partial | ⚠️ Partial | ✅ **Immune** |
| **Account Takeover** | ❌ High Risk | ❌ High Risk | ⚠️ Medium Risk | ✅ **Low Risk** |

### Magic Link Security Context

**Important distinction:**
- Magic links are used **once** to establish passkey (setup phase)
- After setup, user authenticates with **passkey only** (no email dependency)
- This is fundamentally different from email OTP, which relies on email for every login

**Magic link vulnerabilities mitigated:**
- ⚠️ **Email compromise** - Only affects initial setup, not ongoing authentication
- ⚠️ **Link interception** - Time-limited (30 min), purpose-scoped, one-time use
- ⚠️ **Phishing** - Can be mitigated with sender verification, HTTPS enforcement
- ⚠️ **Auto-click scanners** - Use single-use token tracking if needed

**Why this pattern works:**
1. Magic link provides **convenient, secure onboarding** (no shared secrets)
2. Passkey provides **ongoing phishing-resistant authentication** (FIDO2)
3. Email is only attack surface during **initial 30-minute setup window**
4. After setup, email compromise doesn't affect account security

### Industry Standards & Adoption

**NIST SP 800-63-4 (2025):**
- Mandates phishing-resistant MFA for AAL2 and AAL3
- Explicitly endorses FIDO2/WebAuthn passkeys
- Deprecates SMS-based authentication
- Recognizes synced passkeys as AAL2, device-bound as AAL3

**FIDO Alliance (2024-2025):**
- Passkey adoption doubled in 2024
- Over 15 billion online accounts support passkeys
- Hundreds of millions of new passkey users expected in 2025
- Large and growing proportion of world's most visited websites support passkeys

**Government mandates:**
- OMB M-22-09 requires phishing-resistant MFA for federal agencies
- Executive Order 14028 emphasizes passwordless authentication
- Cybersecurity agencies worldwide recommending FIDO2/WebAuthn

### Real-World Security Impact

**With traditional passwords + 2FA:**
- Users must remember passwords (leading to weak/reused passwords)
- 2FA codes can be phished in real-time attacks
- Account recovery often bypasses 2FA entirely
- Dark web markets sell billions of credentials
- Average cost of data breach: $4.45M (2024)

**With magic links + passkeys:**
- No passwords to remember, guess, or steal
- Phishing sites cannot capture authentication
- No credentials to sell on dark web
- Device-bound security (physical possession required)
- Biometric verification prevents unauthorized device use

### Bottom Line

**Magic links + passkeys provide:**
1. ✅ **Phishing-resistant** - Cryptographically bound to domain (FIDO2)
2. ✅ **No shared secrets** - Private keys never transmitted
3. ✅ **Multi-factor by default** - Device + biometric
4. ✅ **No password vulnerabilities** - Immune to all password attacks
5. ✅ **NIST compliant** - Meets 2025 AAL2/AAL3 requirements
6. ✅ **Industry standard** - Adopted by billions of accounts worldwide

**Traditional authentication (passwords + SMS/Email/TOTP):**
- ❌ Phishable, replayable, interceptable
- ❌ Relies on user-chosen secrets
- ❌ Vulnerable to social engineering
- ❌ Database breaches expose credentials
- ❌ Does not meet 2025 security standards

**The security gap is not incremental - it's categorical. Passkeys eliminate entire classes of attacks that plague traditional authentication.**

## Data Model

### Database Schema

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_credentials.rb
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

**Why binary for credential_id and public_key:**
- WebAuthn credentials are binary data, not strings
- Efficient storage and comparison
- Direct compatibility with webauthn-ruby gem

**Why JSON for transports and metadata:**
- Flexible storage for authenticator capabilities
- FIDO metadata includes complex nested structures
- Easy to query and display in UI

### Models

```ruby
class User < ApplicationRecord
  has_many :credentials, dependent: :destroy

  def passkey_registered?
    credentials.exists?
  end

  def primary_credential
    credentials.order(last_used_at: :desc).first
  end

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
  scope :backed_up, -> { where(backed_up: true) }
  scope :by_last_used, -> { order(last_used_at: :desc) }

  def flag_as_compromised!
    update!(compromised: true)
    Rails.logger.warn "Credential #{id} flagged as compromised for user #{user_id}"
    PasskeyMailer.credential_compromised(self).deliver_later
  end

  def last_credential?
    user.credentials.count == 1
  end
end
```

## Authentication Flow

### Initial Setup (Admin-Controlled)

1. Admin clicks "Send Passkey Link" for user
2. Email sent with magic link containing signed_id token
3. User clicks link → auto-login via token verification
4. User clicks "Create Passkey" → WebAuthn registration ceremony
5. User redirected to dashboard

### Subsequent Logins

1. User visits /login
2. Clicks "Sign in with passkey"
3. Browser shows WebAuthn modal
4. User authenticates (Touch ID/Face ID/security key)
5. User logged in

## Session-Based Challenge Storage

**Why session instead of database:**
- ✅ Simpler implementation (no table, no cleanup job)
- ✅ Automatic expiration when session expires
- ✅ Session-scoped security (challenge tied to specific browser)
- ✅ Single-use enforcement via `session.delete()`
- ✅ Encrypted by default (Rails session encryption)

**Challenge lifecycle:**
```ruby
# 1. Generate and store in session
session[:webauthn_challenge] = options.challenge
session[:webauthn_challenge_created_at] = Time.current
session[:webauthn_user_id] = user.id

# 2. Retrieve and validate (single-use)
challenge = session.delete(:webauthn_challenge)
created_at = session.delete(:webauthn_challenge_created_at)

# 3. Validate expiration (10 minutes)
if Time.current - created_at > 10.minutes
  return render json: { error: 'Challenge expired' }, status: :unprocessable_entity
end
```

## Magic Links for Passkey Setup

Magic links enable secure, time-limited access for users to set up their passkeys without passwords. This pattern uses Rails' built-in `signed_id` feature.

### How Magic Links Work

1. Admin generates a cryptographically signed token containing the user's ID
2. Token is sent via email with expiration time
3. User clicks link, Rails verifies signature and finds user
4. User is auto-logged in temporarily
5. User redirected to passkey setup page

### User Model

```ruby
class User < ApplicationRecord
  # Generate time-limited token for passkey setup
  def generate_magic_link_token
    signed_id(expires_in: 30.minutes, purpose: :passkey_setup)
  end
end
```

**Why `signed_id`?**
- Built into Rails (no additional gems)
- Cryptographically signed (tamper-proof)
- Time-limited expiration
- Purpose-scoped (can't be reused for other features)
- Works with any ID type (including UUIDs)

### SessionsController

```ruby
class SessionsController < ApplicationController
  skip_before_action :require_authentication, only: [:new, :magic_link]

  def new
    # Login page with passkey button
  end

  def magic_link
    # Verify signed_id token
    user = User.find_signed!(
      params[:token],
      purpose: :passkey_setup
    )

    # Auto-login user
    login(user)

    # Redirect to passkey setup page
    redirect_to new_credential_path, notice: "Welcome! Let's set up your passkey."

  rescue ActiveSupport::MessageVerifier::InvalidSignature
    redirect_to login_path, alert: "Invalid or expired setup link. Please contact an administrator."
  end

  def destroy
    logout
    redirect_to login_path, notice: "Logged out successfully"
  end
end
```

**Security features:**
- `find_signed!` raises exception on invalid/expired tokens
- Purpose validation prevents token reuse
- Automatic expiration after 30 minutes
- Signature prevents tampering

### UsersController (Admin Actions)

```ruby
class UsersController < ApplicationController
  before_action :require_admin, only: [:send_passkey_setup_link]

  rate_limit to: 3, within: 1.hour,
             by: -> { [current_user.id, params[:id]] },
             only: :send_passkey_setup_link

  def send_passkey_setup_link
    user = User.find(params[:id])
    token = user.generate_magic_link_token

    # Send email with magic link
    PasskeyMailer.setup_passkey(user, token).deliver_later

    # Log admin action
    Rails.logger.info "Admin #{current_user.email} sent passkey setup link to #{user.email}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "user_#{user.id}_actions",
          partial: "users/actions",
          locals: { user: user, link_sent: true }
        )
      end
    end
  end
end
```

**Rate limiting protects against:**
- Admin accidentally spamming users
- Malicious admin abuse
- Email quota exhaustion

### PasskeyMailer

```ruby
class PasskeyMailer < ApplicationMailer
  def setup_passkey(user, token)
    @user = user
    @magic_link = magic_link_url(token)
    @expires_at = 30.minutes.from_now

    mail(
      to: user.email,
      subject: "Set up your passkey for #{ENV.fetch('APP_NAME', 'Your App')}"
    )
  end
end
```

### Email Template

```erb
<!-- app/views/passkey_mailer/setup_passkey.html.erb -->
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
</head>
<body style="font-family: sans-serif; line-height: 1.6; color: #333;">
  <div style="max-width: 600px; margin: 0 auto; padding: 20px;">
    <h1 style="color: #1a1a1a;">Set up your passkey</h1>

    <p>Hello <%= @user.name %>,</p>

    <p>
      An administrator has invited you to set up a passkey for your account.
      Passkeys are a secure and convenient way to sign in using your fingerprint,
      face, or device screen lock.
    </p>

    <div style="margin: 30px 0;">
      <a href="<%= @magic_link %>"
         style="display: inline-block; padding: 12px 24px; background-color: #3b82f6; color: white; text-decoration: none; border-radius: 6px; font-weight: bold;">
        Set up passkey
      </a>
    </div>

    <p style="color: #666; font-size: 14px;">
      This link will expire at <%= @expires_at.strftime('%I:%M %p %Z on %B %d, %Y') %>
      (30 minutes from now).
    </p>

    <hr style="margin: 30px 0; border: none; border-top: 1px solid #e5e5e5;">

    <h2 style="font-size: 18px;">What are passkeys?</h2>
    <ul>
      <li>More secure than passwords (can't be phished or stolen)</li>
      <li>Faster sign-in (just use your fingerprint or face)</li>
      <li>Work across your devices (iPhone, MacBook, etc.)</li>
      <li>No passwords to remember</li>
    </ul>

    <p style="color: #666; font-size: 12px; margin-top: 30px;">
      If you didn't request this, please contact your administrator.
    </p>
  </div>
</body>
</html>
```

### Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Magic link authentication
  get '/login/:token', to: 'sessions#magic_link', as: :magic_link

  # Admin can send setup links
  resources :users do
    member do
      post :send_passkey_setup_link
    end
  end
end
```

### Testing Magic Links

```ruby
# test/system/passkey_authentication_test.rb
test "user registers first passkey via magic link" do
  # Generate magic link token
  token = @user.generate_magic_link_token

  # Visit magic link
  visit magic_link_path(token)

  # Should be auto-logged in and redirected to setup page
  assert_current_path new_credential_path
  assert_text "Set up your passkey"

  # Click create passkey button
  click_button "Create passkey"

  # Virtual authenticator handles WebAuthn ceremony
  assert_current_path jobs_path, wait: 5

  # Verify credential was created
  @user.reload
  assert @user.passkey_registered?
end

test "expired magic link is rejected" do
  # Travel forward 31 minutes
  travel 31.minutes do
    token = @user.generate_magic_link_token
  end

  visit magic_link_path(token)

  assert_current_path login_path
  assert_text "Invalid or expired setup link"
end

test "admin can send passkey setup link" do
  login_as(@admin)
  visit users_path

  within "#user_#{@user.id}" do
    click_button "Send Setup Link"
  end

  # Verify email was sent
  assert_emails 1
  email = ActionMailer::Base.deliveries.last
  assert_equal [@user.email], email.to
  assert_match "Set up your passkey", email.subject
  assert_match magic_link_url(@user.generate_magic_link_token), email.body.to_s
end
```

### Security Considerations

**Token Security:**
- Cryptographically signed (uses Rails secret_key_base)
- Time-limited (30 minutes)
- Purpose-scoped (can't be used for other features)
- Single-use is optional (consider adding used_at timestamp if needed)

**Email Security:**
- Use HTTPS for magic link URLs
- Short expiration time reduces window of attack
- Log all magic link sends for audit trail
- Rate limit magic link sends to prevent abuse

**Alternative: Single-Use Tokens**

For higher security, track used tokens:

```ruby
class User < ApplicationRecord
  def generate_magic_link_token
    # Store used_at timestamp to make single-use
    update_column(:magic_link_used_at, nil)
    signed_id(expires_in: 30.minutes, purpose: :passkey_setup)
  end

  def verify_magic_link!
    raise "Magic link already used" if magic_link_used_at && magic_link_used_at > 30.minutes.ago
    update_column(:magic_link_used_at, Time.current)
  end
end

# In SessionsController
def magic_link
  user = User.find_signed!(params[:token], purpose: :passkey_setup)
  user.verify_magic_link!  # Raises if already used
  login(user)
  redirect_to new_credential_path
end
```

## Controller Implementation

### WebAuthn Registration

```ruby
class Webauthn::RegistrationController < ApplicationController
  rate_limit to: 5, within: 15.minutes,
             by: -> { params[:user_id] || session[:webauthn_user_id] }

  def begin
    user = User.find(params[:user_id] || current_user.id)

    options = WebAuthn::Credential.options_for_create(
      user: {
        id: user.id,
        name: user.email,
        display_name: user.name
      },
      exclude: user.credentials.pluck(:credential_id),
      authenticator_selection: {
        resident_key: 'preferred',
        user_verification: 'preferred'
      }
    )

    # Store challenge in session (single-use)
    session[:webauthn_challenge] = options.challenge
    session[:webauthn_challenge_created_at] = Time.current
    session[:webauthn_user_id] = user.id

    render json: options
  end

  def complete
    # Retrieve challenge from session (single-use)
    challenge = session.delete(:webauthn_challenge)
    created_at = session.delete(:webauthn_challenge_created_at)
    user_id = session.delete(:webauthn_user_id)

    # Validate presence and expiration
    unless challenge && created_at && user_id
      return render json: { error: 'No active registration challenge' },
                    status: :unprocessable_entity
    end

    if Time.current - created_at > 10.minutes
      return render json: { error: 'Challenge expired' },
                    status: :unprocessable_entity
    end

    user = User.find(user_id)
    webauthn_credential = WebAuthn::Credential.from_create(params[:credential])

    begin
      webauthn_credential.verify(challenge)

      credential = user.credentials.create!(
        credential_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count,
        aaguid: webauthn_credential.aaguid,
        transports: webauthn_credential.transports || []
      )

      login(user)
      render json: { success: true, redirect_url: jobs_path }

    rescue WebAuthn::Error => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end
end
```

### WebAuthn Authentication

```ruby
class Webauthn::AuthenticationController < ApplicationController
  skip_before_action :require_authentication

  rate_limit to: 10, within: 15.minutes, by: -> { request.remote_ip }

  def begin
    options = WebAuthn::Credential.options_for_get(
      user_verification: 'preferred'
    )

    session[:webauthn_challenge] = options.challenge
    session[:webauthn_challenge_created_at] = Time.current

    render json: options
  end

  def complete
    challenge = session.delete(:webauthn_challenge)
    created_at = session.delete(:webauthn_challenge_created_at)

    unless challenge && created_at
      return render json: { error: 'No active authentication challenge' },
                    status: :unauthorized
    end

    credential_id = Base64.decode64(params[:credential][:id])
    credential = Credential.find_by!(credential_id: credential_id)

    webauthn_credential = WebAuthn::Credential.from_get(params[:credential])

    begin
      webauthn_credential.verify(
        challenge,
        public_key: credential.public_key,
        sign_count: credential.sign_count
      )

      # Check for signature counter decrease (cloned authenticator)
      if webauthn_credential.sign_count > 0 &&
         webauthn_credential.sign_count <= credential.sign_count
        credential.flag_as_compromised!
        return render json: { error: 'Invalid authenticator' },
                      status: :unauthorized
      end

      credential.update!(
        sign_count: webauthn_credential.sign_count,
        last_used_at: Time.current
      )

      login(credential.user)
      render json: { success: true, redirect_url: jobs_path }

    rescue WebAuthn::Error => e
      render json: { error: e.message }, status: :unauthorized
    end
  end
end
```

## Stimulus JavaScript Controller

```javascript
// app/javascript/controllers/webauthn_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    beginUrl: String,
    completeUrl: String,
    mode: String  // "registration" or "authentication"
  }

  static targets = ["submitButton", "errorContainer"]

  async start(event) {
    event.preventDefault()

    if (this.modeValue === "registration") {
      await this.startRegistration()
    } else {
      await this.startAuthentication()
    }
  }

  async startRegistration() {
    try {
      this.setLoading(true)

      // 1. Get registration options from server
      const beginResponse = await fetch(this.beginUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        }
      })

      if (!beginResponse.ok) throw new Error('Failed to begin registration')

      const options = await beginResponse.json()

      // 2. Parse options using native browser API
      const publicKeyOptions = PublicKeyCredential.parseCreationOptionsFromJSON(options)

      // 3. Create credential
      const credential = await navigator.credentials.create({
        publicKey: publicKeyOptions
      })

      // 4. Send credential to server using native toJSON()
      const completeResponse = await fetch(this.completeUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken
        },
        body: JSON.stringify({ credential: credential.toJSON() })
      })

      if (!completeResponse.ok) throw new Error('Failed to complete registration')

      const result = await completeResponse.json()

      // 5. Redirect on success
      if (result.success && result.redirect_url) {
        window.location.href = result.redirect_url
      }

    } catch (error) {
      this.handleError(error)
    } finally {
      this.setLoading(false)
    }
  }

  handleError(error) {
    let message = 'An error occurred. Please try again.'

    // Map WebAuthn errors to user-friendly messages
    if (error.name === 'NotAllowedError') {
      message = 'Sign-in was canceled. Please try again.'
    } else if (error.name === 'InvalidStateError') {
      message = 'This passkey is already registered on this device.'
    } else if (error.name === 'NotSupportedError') {
      message = 'Passkeys are not supported on this browser.'
    }

    if (this.hasErrorContainerTarget) {
      this.errorContainerTarget.textContent = message
      this.errorContainerTarget.classList.remove('hidden')
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ''
  }
}
```

## Configuration

### WebAuthn Configuration

```ruby
# config/initializers/webauthn.rb
WebAuthn.configure do |config|
  config.origin = if Rails.env.production?
    ENV.fetch('WEBAUTHN_ORIGIN')  # e.g., "https://intaqt.example.com"
  else
    'http://localhost:3000'
  end

  config.rp_name = ENV.fetch('WEBAUTHN_RP_NAME', 'Your App Name')

  config.rp_id = if Rails.env.production?
    ENV.fetch('WEBAUTHN_RP_ID')  # e.g., "intaqt.example.com"
  else
    'localhost'
  end

  config.credential_options_timeout = 60_000  # 60 seconds
  config.encoding = :base64
  config.algorithms = ['ES256', 'RS256']
end
```

**Configuration notes:**
- `origin` must match the URL exactly (including protocol and port)
- `rp_id` is the domain without protocol/port
- Environment-specific configuration for development/staging/production

### Session Store Configuration

**CRITICAL:** Passkey authentication requires database-backed sessions to store WebAuthn challenges.

```ruby
# config/initializers/session_store.rb
Rails.application.config.session_store :active_record_store,
  key: "_your_app_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax,
  expire_after: 1.week
```

**Why database-backed sessions:**
- ✅ **Larger storage** - WebAuthn challenges (~170 bytes) fit comfortably
- ✅ **Server-side storage** - Challenges never sent to client
- ✅ **Better security** - Session data encrypted in database
- ✅ **Automatic cleanup** - Expired sessions removed automatically

**Session configuration explained:**
- `key` - Cookie name (customize for your app)
- `secure: true` - Only send cookie over HTTPS in production
- `httponly: true` - Prevent JavaScript access to session cookie
- `same_site: :lax` - CSRF protection, allows navigation from external sites
- `expire_after: 1.week` - Auto-logout after inactivity

**Required migration:**
```bash
# Generate sessions table migration
bin/rails generate active_record:session_migration
bin/rails db:migrate
```

**Session table schema:**
```ruby
create_table :sessions do |t|
  t.string :session_id, null: false
  t.text :data
  t.timestamps
end

add_index :sessions, :session_id, unique: true
add_index :sessions, :updated_at
```

### FIDO Metadata Configuration (Optional)

For displaying device names and authenticator information:

```ruby
# config/initializers/fido_metadata.rb
FidoMetadata.configure do |config|
  # Use Rails cache for storing fetched metadata
  # The gem automatically handles caching with a 24-hour TTL
  config.cache_backend = Rails.cache
end
```

**What this provides:**
- Device names: "YubiKey 5 NFC", "Touch ID (MacBook Pro)", etc.
- Authenticator icons and descriptions
- FIDO certification status
- Attachment hints (platform vs cross-platform)

**How it works:**
- First request for each AAGUID downloads metadata from FIDO MDS
- Metadata cached for 24 hours via Rails cache
- Subsequent requests use cached data
- No pre-population needed

**Without this:**
- All devices show "Security Key" or "Unknown Authenticator"
- Still works, just less user-friendly

## Rate Limiting

```ruby
# config/environments/production.rb
Rails.application.configure do
  config.action_controller.rate_limiting_cache_store = :solid_cache_store
end

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  rescue_from ActionController::RateLimitExceeded do |exception|
    respond_to do |format|
      format.json do
        render json: {
          error: "Rate limit exceeded. Please try again later.",
          retry_after: exception.retry_after
        }, status: :too_many_requests
      end

      format.html do
        flash[:alert] = "Too many attempts. Please try again in #{exception.retry_after} seconds."
        redirect_back fallback_location: root_path
      end
    end
  end
end
```

## Testing with Virtual Authenticator

```ruby
# test/application_system_test_case.rb
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  def setup_virtual_authenticator(options = {})
    @virtual_authenticator_id = driver.add_virtual_authenticator({
      protocol: 'ctap2',           # FIDO2 protocol
      transport: 'internal',       # Platform authenticator
      hasResidentKey: true,        # Supports discoverable credentials
      hasUserVerification: true,   # Supports biometrics/PIN
      isUserVerified: true         # User is verified by default
    }.merge(options))
  end

  def remove_virtual_authenticator
    if @virtual_authenticator_id
      driver.remove_virtual_authenticator(@virtual_authenticator_id)
      @virtual_authenticator_id = nil
    end
  end
end

# test/system/passkey_authentication_test.rb
class PasskeyAuthenticationTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    setup_virtual_authenticator
  end

  teardown do
    remove_virtual_authenticator
  end

  test "user registers first passkey via magic link" do
    token = @user.generate_magic_link_token
    visit magic_link_path(token)

    assert_current_path new_credential_path
    assert_text "Set up your passkey"

    click_button "Create passkey"

    # Virtual authenticator handles WebAuthn ceremony
    assert_current_path jobs_path, wait: 5

    @user.reload
    assert @user.passkey_registered?
  end
end
```

## Security Considerations

### Signature Counter Validation

Critical for detecting cloned authenticators:

```ruby
if webauthn_credential.sign_count > 0 &&
   webauthn_credential.sign_count <= credential.sign_count
  # Counter decreased or didn't increase = possible clone
  credential.flag_as_compromised!
  Rails.logger.warn "Signature counter anomaly detected"
  return render json: { error: 'Invalid authenticator' }, status: :unauthorized
end
```

### Origin Validation

The webauthn-ruby gem automatically verifies:
- Origin in `clientDataJSON` matches configured origin exactly
- RP ID hash in `authenticatorData` matches SHA-256(rp_id)
- Must match exactly (https vs http, port, subdomain)

### FIDO Metadata

Optionally fetch authenticator metadata:

```ruby
# Gemfile
gem 'fido_metadata'

# app/jobs/fetch_authenticator_metadata_job.rb
class FetchAuthenticatorMetadataJob < ApplicationJob
  def perform(credential_id)
    credential = Credential.find(credential_id)
    return if credential.aaguid.blank?

    store = FidoMetadata::Store.new
    statement = store.fetch_statement(aaguid: credential.aaguid)

    if statement
      credential.update!(
        device_name: statement.description,
        metadata: {
          description: statement.description,
          is_fido_certified: statement.fido_certified?
        }
      )
    end
  rescue KeyError
    credential.update!(device_name: "Unknown Authenticator")
  end
end

# Trigger after credential creation
class Credential < ApplicationRecord
  after_create :enqueue_metadata_fetch

  private

  def enqueue_metadata_fetch
    FetchAuthenticatorMetadataJob.perform_later(id)
  end
end
```

## Required Gems

```ruby
# Gemfile
gem 'webauthn'
gem 'fido_metadata'  # Optional, for device metadata
```

## Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
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

  get '/login', to: 'sessions#new'
  get '/login/:token', to: 'sessions#magic_link', as: :magic_link
  delete '/logout', to: 'sessions#destroy'
end
```

## References

- [W3C WebAuthn Specification](https://www.w3.org/TR/webauthn-3/)
- [webauthn-ruby gem](https://github.com/cedarcode/webauthn-ruby)
- [FIDO Alliance](https://fidoalliance.org/passkeys/)
- [Selenium Virtual Authenticator](https://www.selenium.dev/documentation/webdriver/interactions/virtual_authenticator/)
