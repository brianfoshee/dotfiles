# Authorization and Roles

A small fixed role set plus explicit resource-access records, with most
authorization falling out of association scoping rather than explicit checks.
No policy objects, no permissions table.

## Contents

- [Roles](#roles)
- [Identity vs User](#identity-vs-user)
- [Four layers of authorization](#four-layers-of-authorization)
- [Resource access records](#resource-access-records)
- [Access cascades through associations](#access-cascades-through-associations)
- [Public and API access](#public-and-api-access)
- [Testing](#testing)
- [What to avoid](#what-to-avoid)
- [References](#references)

## Roles

Four roles cover it: **owner** (account creator, one per account, can administer
everyone but themselves), **admin** (can administer users and content, but not
the owner), **member** (the default; administers only what they created), and
**system** (per-account automation user, hidden from user lists, never
notified).

The enum, the scopes, and every `can_*` predicate live in one concern:

```ruby
# app/models/user/role.rb
module User::Role
  extend ActiveSupport::Concern

  included do
    enum :role, %i[ owner admin member system ].index_by(&:itself), scopes: false

    scope :owner, -> { where(active: true, role: :owner) }
    scope :admin, -> { where(active: true, role: %i[ owner admin ]) }
    scope :member, -> { where(active: true, role: :member) }
    scope :active, -> { where(active: true, role: %i[ owner admin member ]) }

    def admin?
      super || owner?
    end
  end

  def can_change?(other)     = (admin? && !other.owner?) || other == self
  def can_administer?(other) = admin? && !other.owner? && other != self

  def can_administer_board?(board) = admin? || board.creator == self
  def can_administer_card?(card)   = admin? || card.creator == self

  def sole_owner? = active? && owner? && account.users.owner.excluding(self).none?
end
```

Only `admin?` cascades — an owner is an admin for permission purposes. Leave
`member?` alone: "is specifically a member" is a different question from "may
act administratively," and cascading every predicate blurs it.

`can_change?` lets users change themselves, so self-deactivation needs a
`sole_owner?` guard, checked in a `before_action` after the permission gate.

```ruby
create_table :users, id: :string do |t|
  t.references :account, type: :string, null: false, foreign_key: true
  t.references :identity, type: :string, foreign_key: true  # nil for deactivated users
  t.string :role, default: "member", null: false
  t.boolean :active, default: true, null: false
  t.datetime :verified_at
  t.timestamps
end
```

Active state is separate from role, so deactivating doesn't discard which role
someone had.

Good permission methods name a resource and combine role with ownership —
`can_administer_board?(board)`. Bad ones enumerate capabilities
(`can_edit_board_name?`), bind to a resource type (`board_admin`,
`comment_moderator`), or encode billing state (`trial_member`, `paid_member`).
Roles should be stable enough that new features never add one; anything that
varies per resource belongs in an access record, and anything that varies over
time belongs in the account.

## Identity vs User

For multi-tenant SaaS, split the global person from the per-account membership.
One `Identity` (an email address, sessions, magic links) can own `User` records
in several accounts, deactivation doesn't lose the identity, and cross-account
features have somewhere to hang.

```ruby
class Identity < ApplicationRecord
  has_many :users
  has_many :sessions
  has_many :magic_links
end

class User < ApplicationRecord
  belongs_to :account
  belongs_to :identity, optional: true
end
```

Setting the identity resolves the account-scoped user:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account

  def identity=(identity)
    super
    self.user = identity.users.find_by(account: account) if identity.present?
  end
end
```

Sign-in shouldn't reveal which emails exist: answer an unknown address exactly
as a known one, sending both to the same code-entry page. Bind a typed code to
the browser that asked for it with a signed cookie holding the requested email,
and compare the two with `secure_compare`.

## Four layers of authorization

**1. Account access** — the authenticated identity has an active user here.

```ruby
module Authorization
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_access_account, if: -> { Current.account.present? }
  end

  private
    def ensure_can_access_account
      redirect_to root_path if Current.user.blank? || !Current.user.active?
    end

    def ensure_admin
      head :forbidden unless Current.user.admin?
    end

    def ensure_staff
      head :forbidden unless Current.identity.staff?
    end
end
```

`ensure_admin` reads the account-scoped role; `ensure_staff` reads the
cross-account identity.

Controllers state their opt-outs with named macros, never a raw
`skip_before_action`:

```ruby
module Authentication
  extend ActiveSupport::Concern

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      before_action :resume_session, **options
      allow_unauthorized_access **options
    end

    def require_unauthenticated_access(**options)
      allow_unauthenticated_access **options
      before_action :redirect_authenticated_user, **options
    end

    def disallow_account_scope(**options)
      skip_before_action :require_account, **options
      before_action :redirect_tenanted_request, **options
    end
  end
end

module Authorization
  extend ActiveSupport::Concern

  class_methods do
    def allow_unauthorized_access(**options)
      skip_before_action :ensure_can_access_account, **options
    end
  end
end
```

**2. Scoping** — the bulk of authorization, and the part that can't be
forgotten. Loading through the user's associations means no access, no record:

```ruby
def set_board
  @board = Current.user.boards.find(params[:id])  # RecordNotFound if no access
end
```

Nested controllers share the lookup through a concern, so none writes its own
`find`:

```ruby
module CardScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_card
  end

  private
    def set_card
      @card = Current.user.accessible_cards.find_by!(number: params[:card_id])
    end
end

class Cards::ClosuresController < ApplicationController
  include CardScoped
end
```

A `BoardScoped` concern carries the board's admin guard alongside its lookup.

**3. Action permissions** — for destructive actions, on top of scoping:

```ruby
before_action :ensure_permission_to_admin_board, only: %i[ update destroy ]

def ensure_permission_to_admin_board
  head :forbidden unless Current.user.can_administer_board?(@board)
end
```

**4. Whole-controller guards** — `before_action :ensure_admin`.

## Resource access records

```ruby
create_table :accesses, id: :string do |t|
  t.references :board, type: :string, null: false, foreign_key: true
  t.references :user, type: :string, null: false, foreign_key: true
  t.references :account, type: :string, null: false, foreign_key: true
  t.string :involvement, default: "access_only", null: false
  t.datetime :accessed_at
  t.timestamps
end
```

A board is either all-access (every active user gets an access record, managed
by callbacks) or selective (explicit grants; the creator gets one with
`watching`). Involvement separates seeing a board from being notified about it:
`enum :involvement, %i[ access_only watching ].index_by(&:itself), default: :access_only`.

```ruby
module Board::Accessible
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :destroy
  end

  def grant_access_to(users)
    Array(users).each { |user| accesses.find_or_create_by!(user: user, involvement: :access_only) }
  end

  def revoke_access_from(users) = accesses.where(user: users).destroy_all

  def revise_access(granted:, revoked:)
    transaction do
      grant_access_to(granted) if granted.present?
      revoke_access_from(revoked) if revoked.present?
    end
  end

  def accessible_to?(user) = accesses.exists?(user: user)
  def access_for(user)     = accesses.find_by(user: user)
end
```

Revoking access has to clean up what it leaves behind — mentions, notifications,
and watches that reference a board the user can no longer see:

```ruby
class Access < ApplicationRecord
  after_destroy_commit :clean_inaccessible_data_later

  private
    def clean_inaccessible_data_later
      CleanInaccessibleDataJob.perform_later(user, board)
    end
end
```

Cleanup is async, and records also move to boards a user can't see, so don't
rely on it alone. Filter derived records like pins through current access when
they're read, limit notification recipients to users with access when they're
created, and have the cleanup job re-check `accessible_to?` in case access came
back before it ran.

## Access cascades through associations

Access is recorded at one level and inherited downward, so cards and comments
need no access records of their own:

```ruby
module User::Accessor
  extend ActiveSupport::Concern

  included do
    has_many :accesses
    has_many :boards, through: :accesses
    has_many :accessible_cards, through: :boards, source: :cards
    has_many :accessible_comments, through: :accessible_cards, source: :comments
  end
end
```

## Public and API access

```ruby
class Public::BoardsController < ApplicationController
  allow_unauthenticated_access

  def show
    @board = Board.find_by_published_key(params[:board_id])
    head :not_found unless @board&.published?
  end
end
```

Bearer tokens authenticate JSON requests only; any other format gets a 401
rather than a login redirect. Each token is read or write, and a read token
allows only GET and HEAD:

```ruby
def authenticate_by_bearer_token
  return unless request.authorization.to_s.include?("Bearer")

  if request.format.json?
    authenticate_or_request_with_http_token do |token|
      Current.identity = Identity.find_by_access_token(token, method: request.method)
    end
  else
    request_http_token_authentication
  end
end
```

```ruby
class Identity::AccessToken < ApplicationRecord
  belongs_to :identity

  has_secure_token
  enum :permission, %w[ read write ].index_by(&:itself), default: :read

  def allows?(method) = method.in?(%w[ GET HEAD ]) || write?
end

class Identity < ApplicationRecord
  def self.find_by_access_token(token, method:)
    access_token = Identity::AccessToken.find_by(token: token)
    access_token.identity if access_token&.allows?(method)
  end
end
```

A controller that serves files to token clients, such as Active Storage's,
overrides the JSON-only check.

## Testing

Permission predicates are model tests; the enforcement is a controller test.
Cover the negative cases — self-administration and the owner exception are where
these go wrong.

```ruby
test "admin can administer other users except owner and self" do
  admin = users(:admin)
  assert admin.can_administer?(users(:member))
  assert_not admin.can_administer?(users(:owner))
  assert_not admin.can_administer?(admin)
end

test "member cannot destroy a board they didn't create" do
  sign_in_as :member
  delete board_url(boards(:created_by_admin))
  assert_response :forbidden
end
```

## What to avoid

**Refetching then checking.** `Board.find(params[:id])` followed by a manual
`accessible_to?` is a check you can forget. Scope through `Current.user`
instead, and reserve explicit predicates for administrative actions.

**Role explosion.** `viewer / commenter / editor / publisher / moderator /
admin / super_admin / owner` is a permission system pretending to be roles.
Four roles plus access records express the same thing and stay constant.

**A permissions table.** Rows of `(user, resource_type, resource_id, action)`
move authorization logic into data, where it can't be read or tested as a unit.
Keep the rules in code and the grants in a join table.

**Authorization in model callbacks.** `before_update :ensure_can_update` fires
in tests, console sessions, and background jobs where `Current.user` isn't what
you think. Authorization is a request-time concern; keep it in controllers.
The exception is a side effect that widens access, like a card move granting
its assignees access to the new board: gate it where it happens with
`Current.user&.can_administer_board?(board)`, so it fails closed in jobs and the
console. Audit every indirect write to access records, not just the
access-management controller.

**Trusting Active Storage's signed URLs.** The blob and representation
controllers inherit `ActiveStorage::BaseController`, not `ApplicationController`,
so none of your filters run and anyone holding a signed id can fetch the file.
Include a concern in them that authenticates and checks
`attachment.record.try(:accessible_to?, Current.user)`, lets an unattached blob
through only within its own account, and re-appends `set_representation` so
variants are processed after the check. Authenticate
`DirectUploadsController` too, and keep HTML, SVG and XML in
`content_types_to_serve_as_binary`.

## References

- [Controller filters](https://guides.rubyonrails.org/action_controller_overview.html#filters)
- [Enum](https://api.rubyonrails.org/classes/ActiveRecord/Enum.html) · [Current Attributes](https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html)
