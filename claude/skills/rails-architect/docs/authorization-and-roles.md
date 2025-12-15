# Authorization and Roles in Rails Applications

Production-proven patterns for user roles and authorization in Rails applications, based on real-world implementations from 37signals/Basecamp.

## Core Philosophy

**Simple roles + explicit resource access** beats complex permission systems.

- **Minimal role set** - 3-4 roles maximum (owner, admin, member, system)
- **Authorization through structure** - Use associations for access control, not conditionals
- **Role + ownership combination** - Creators manage their content, admins manage everything
- **Separation of concerns** - Identity (global) vs User (account-specific)

## Role Definition

### The Four Standard Roles

```ruby
# app/models/user/role.rb
module User::Role
  extend ActiveSupport::Concern

  included do
    enum :role, %i[ owner admin member system ].index_by(&:itself), scopes: false
  end
end
```

**owner** - Account creator with highest privileges
- Only one per account (business logic enforced)
- Can administer all resources and users except themselves
- Automatically treated as admin for permission checks

**admin** - Administrative users
- Can administer boards, content, and other users
- Cannot administer the owner
- Full access to all administrative actions

**member** - Regular users (default)
- Standard access to resources they're granted access to
- Can administer content they created
- Cannot administer other users

**system** - Internal automation user
- Created automatically for each account
- Used for automated actions (notifications, background jobs)
- Excluded from user lists and never receives notifications

### Database Schema

```ruby
create_table :users do |t|
  t.uuid :account_id, null: false
  t.uuid :identity_id  # Can be nil (deactivated users)
  t.string :role, default: "member", null: false
  t.boolean :active, default: true, null: false
  t.datetime :verified_at
  t.timestamps
end
```

**Key design decisions:**
- Role stored as string (enum in model)
- Active state separate from role (can deactivate without losing role)
- Identity optional (allows user records without active identity)

### Hierarchical Permissions

Make higher roles automatically include lower role permissions:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  include Role

  def admin?
    super || owner?  # Owner is also an admin
  end

  def member?
    super || admin?  # Admin is also a member
  end
end
```

## Role Design Guidelines

### What Makes a Good Role

✅ **Resource-oriented, not permission-oriented**
```ruby
# Good
admin? && can_administer_board?(board)

# Bad (too granular)
can_edit_board_name? || can_change_board_color?
```

✅ **Combined with resource ownership**
```ruby
def can_administer_board?(board)
  admin? || board.creator == self
end
```

✅ **Minimal and stable**
- Roles rarely change after account setup
- New features don't require new roles
- Role count stays constant as app grows

### What Makes a Bad Role

❌ **Granular permission-based roles**
```ruby
# Bad - too many roles
enum :role, %i[ viewer editor publisher admin owner ]
```

❌ **Resource-specific roles**
```ruby
# Bad - roles tied to specific resources
enum :role, %i[ board_admin card_creator comment_moderator ]
```

❌ **Temporary or conditional roles**
```ruby
# Bad - roles that change frequently
enum :role, %i[ trial_member paid_member premium_member ]
```

**Instead:** Use account-level roles + explicit resource-level access grants.

## Authorization Architecture

### Identity vs User Separation

**Critical pattern for multi-tenant SaaS:**

```ruby
# Global user (email address)
class Identity < ApplicationRecord
  has_many :users  # Can have users in multiple accounts
  has_many :sessions
  has_many :magic_links
end

# Account-specific membership
class User < ApplicationRecord
  belongs_to :account
  belongs_to :identity, optional: true

  enum :role, %i[ owner admin member system ]
end
```

**Benefits:**
- One person can join multiple accounts
- Deactivation doesn't lose identity
- Cross-account features (global notifications, staff access)

### Current Attributes Pattern

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account

  def identity=(identity)
    super(identity)
    if identity.present?
      self.user = identity.users.find_by(account: account)
    end
  end
end
```

**Cascade:** Setting identity → automatically finds User for current Account

### Authorization Layers

**Layer 1: Account-Level Access**
```ruby
# app/controllers/concerns/authorization.rb
module Authorization
  extend ActiveSupport::Concern

  included do
    before_action :ensure_can_access_account, if: -> { Current.account.present? }
  end

  private
    def ensure_can_access_account
      redirect_to root_path if Current.user.blank? || !Current.user.active?
    end
end
```

**Purpose:** Ensures authenticated identity has active User in current account.

**Layer 2: Resource Scoping**
```ruby
# Controllers scope through Current.user associations
class BoardsController < ApplicationController
  def set_board
    @board = Current.user.boards.find(params[:id])
  end
end
```

**Purpose:** Authorization through association traversal. No explicit checks needed.

**Layer 3: Action-Level Permissions**
```ruby
class BoardsController < ApplicationController
  before_action :ensure_permission_to_admin_board, only: %i[ update destroy ]

  private
    def ensure_permission_to_admin_board
      head :forbidden unless Current.user.can_administer_board?(@board)
    end
end
```

**Purpose:** Fine-grained permission checks for destructive actions.

**Layer 4: Role-Based Guards**
```ruby
# app/controllers/concerns/authorization.rb
def ensure_admin
  head :forbidden unless Current.user.admin?
end

# Usage in controllers
class WebhooksController < ApplicationController
  before_action :ensure_admin
end
```

**Purpose:** Restrict entire controllers to specific roles.

## Authorization Patterns

### Pattern 1: Role + Ownership

```ruby
# app/models/user/administrator.rb
module User::Administrator
  def can_administer_board?(board)
    admin? || board.creator == self
  end

  def can_administer_card?(card)
    admin? || card.creator == self
  end
end
```

**When to use:** Resource-level administration where creators manage their content.

### Pattern 2: Role + Hierarchy

```ruby
def can_administer?(other_user)
  admin? && !other_user.owner? && other_user != self
end

def can_change?(other_user)
  (admin? && !other_user.owner?) || other_user == self
end
```

**When to use:** User management where role hierarchy matters.

### Pattern 3: Association-Based Access (Implicit)

```ruby
# User model
has_many :accesses
has_many :boards, through: :accesses

# Controller
@board = Current.user.boards.find(params[:id])
# Raises RecordNotFound if no access - no explicit check needed
```

**When to use:** Reading resources with managed access via join tables.

**Benefits:**
- Can't forget authorization check
- Database enforces constraints
- Simpler controller code
- Automatic N+1 prevention opportunities

### Pattern 4: Public Access Exception

```ruby
class Public::BoardsController < ApplicationController
  allow_unauthenticated_access

  def show
    @board = Board.find_by_published_key(params[:board_id])
    head :not_found unless @board&.published?
  end
end
```

**When to use:** Public sharing features that bypass normal authorization.

### Pattern 5: Bearer Token API Access

```ruby
# app/controllers/concerns/api_authentication.rb
def authenticate_by_bearer_token
  if request.authorization.to_s.include?("Bearer")
    authenticate_or_request_with_http_token do |token|
      if identity = Identity.find_by_access_token(token)
        Current.identity = identity
      end
    end
  end
end
```

**When to use:** API endpoints with token-based authentication.

## Resource-Level Access Control

### Board-Level Access Pattern

```ruby
# Migration
create_table :accesses do |t|
  t.uuid :board_id, null: false
  t.uuid :user_id, null: false
  t.uuid :account_id, null: false
  t.string :involvement, default: "access_only", null: false
  t.datetime :accessed_at
  t.timestamps
end

# Model
class Board < ApplicationRecord
  has_many :accesses, dependent: :destroy
  has_many :users, through: :accesses

  # All users vs selective
  attribute :all_access, :boolean, default: true
end
```

**Two access modes:**

**All-access boards** (`all_access: true`)
- All active users automatically get access
- Access records created/destroyed via callbacks

**Selective boards** (`all_access: false`)
- Explicit access grants required
- Creator automatically gets access with "watching" involvement

### Access Management API

```ruby
# app/models/board/accessible.rb
module Board::Accessible
  extend ActiveSupport::Concern

  included do
    has_many :accesses, dependent: :destroy
  end

  # Granting access
  def grant_access_to(users)
    Array(users).each do |user|
      accesses.find_or_create_by!(user: user, involvement: :access_only)
    end
  end

  # Revoking access
  def revoke_access_from(users)
    accesses.where(user: users).destroy_all
  end

  # Batch update
  def revise_access(granted:, revoked:)
    transaction do
      grant_access_to(granted) if granted.present?
      revoke_access_from(revoked) if revoked.present?
    end
  end

  # Check access
  def accessible_to?(user)
    accesses.exists?(user: user)
  end

  def access_for(user)
    accesses.find_by(user: user)
  end
end
```

### Involvement Levels (Optional Enhancement)

```ruby
# app/models/access.rb
class Access < ApplicationRecord
  belongs_to :board
  belongs_to :user

  enum :involvement, { access_only: 0, watching: 1 }
end
```

**access_only** - Can view and interact
**watching** - Receives notifications about activity

### Cascading Data Cleanup

When access is revoked, clean up related data:

```ruby
# app/models/access.rb
class Access < ApplicationRecord
  after_destroy_commit :clean_inaccessible_data_later

  private
    def clean_inaccessible_data_later
      CleanInaccessibleDataJob.perform_later(user, board)
    end
end

# Job removes:
# - Mentions on cards/comments in that board
# - Notifications about events in that board
# - Watches on cards in that board
```

## Permission Methods on User

```ruby
# app/models/user/administrator.rb
module User::Administrator
  # Resource administration
  def can_administer_board?(board)
    admin? || board.creator == self
  end

  def can_administer_card?(card)
    admin? || card.creator == self
  end

  # User administration
  def can_administer?(other)
    admin? && !other.owner? && other != self
  end

  def can_change?(other)
    (admin? && !other.owner?) || other == self
  end

  # Account settings
  def can_administer_account?
    owner?
  end
end
```

**Pattern:** Descriptive method names that combine role + context.

## Scoping Associations for Access

```ruby
# app/models/user/accessor.rb
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

**Pattern:** Cascade access through associations.
- Board access → Card access → Comment access
- No card-level or comment-level access records needed

## Testing Authorization

```ruby
# test/models/user_test.rb
class UserTest < ActiveSupport::TestCase
  test "admin can administer other users except owner" do
    admin = users(:admin)
    member = users(:member)
    owner = users(:owner)

    assert admin.can_administer?(member)
    assert_not admin.can_administer?(owner)
    assert_not admin.can_administer?(admin)  # Can't administer self
  end

  test "creator can administer their own board" do
    member = users(:member)
    board = boards(:created_by_member)

    assert member.can_administer_board?(board)
  end

  test "member cannot administer boards they didn't create" do
    member = users(:member)
    board = boards(:created_by_admin)

    assert_not member.can_administer_board?(board)
  end
end

# test/controllers/boards_controller_test.rb
class BoardsControllerTest < ActionDispatch::IntegrationTest
  test "member cannot destroy board they didn't create" do
    sign_in_as :member
    board = boards(:created_by_admin)

    delete board_url(board)
    assert_response :forbidden
  end

  test "admin can destroy any board" do
    sign_in_as :admin
    board = boards(:created_by_member)

    assert_difference("Board.count", -1) do
      delete board_url(board)
    end
  end
end
```

## Common Anti-Patterns to Avoid

### ❌ Anti-Pattern 1: Checking Permissions Everywhere

```ruby
# Bad - scattered permission checks
def show
  @board = Board.find(params[:id])
  raise Forbidden unless @board.accessible_to?(Current.user)
end

def update
  @board = Board.find(params[:id])
  raise Forbidden unless Current.user.can_administer_board?(@board)
end
```

**Better - Authorization through scoping:**
```ruby
before_action :set_board
before_action :ensure_can_administer, only: %i[ update destroy ]

private
  def set_board
    @board = Current.user.boards.find(params[:id])  # Implicit authorization
  end

  def ensure_can_administer
    head :forbidden unless Current.user.can_administer_board?(@board)
  end
```

### ❌ Anti-Pattern 2: Too Many Roles

```ruby
# Bad - role explosion
enum :role, %i[
  viewer
  commenter
  editor
  publisher
  moderator
  admin
  super_admin
  owner
]
```

**Better - Minimal roles + resource access:**
```ruby
enum :role, %i[ owner admin member system ]

# Use resource-level access grants
has_many :board_accesses
```

### ❌ Anti-Pattern 3: Permissions in Database

```ruby
# Bad - granular permissions table
create_table :permissions do |t|
  t.uuid :user_id
  t.string :resource_type
  t.uuid :resource_id
  t.string :action  # "create", "read", "update", "delete"
end
```

**Better - Structural authorization:**
```ruby
# Role-based permissions in code
def can_administer_board?(board)
  admin? || board.creator == self
end

# Resource access via join table
has_many :boards, through: :accesses
```

### ❌ Anti-Pattern 4: Callbacks for Authorization

```ruby
# Bad - authorization in callbacks
class Card < ApplicationRecord
  before_update :ensure_can_update

  private
    def ensure_can_update
      raise Forbidden unless Current.user.admin?
    end
end
```

**Better - Authorization in controller:**
```ruby
class CardsController < ApplicationController
  before_action :ensure_can_administer, only: %i[ update destroy ]
end
```

**Reason:** Authorization is a controller concern, not a model concern.

## Key Architectural Insights

1. **Authorization by query scoping** - `Current.user.boards.find(id)` is authorization
2. **Minimal roles + explicit access** - Simple role enum + join table for resource access
3. **Identity ≠ User** - Global identity can have users in multiple accounts
4. **No policy objects needed** - Vanilla Rails with concerns is sufficient
5. **Structure over conditionals** - Use associations for access, not if statements
6. **Permission methods on User** - `can_administer_board?` not policy classes
7. **Cascading cleanup** - Revoking access cleans up all related data
8. **Owner can't administer themselves** - Prevents accidental self-removal

## References

- [Rails Authorization Patterns](https://guides.rubyonrails.org/action_controller_overview.html#filters)
- [Enum Documentation](https://api.rubyonrails.org/classes/ActiveRecord/Enum.html)
- [Current Attributes](https://api.rubyonrails.org/classes/ActiveSupport/CurrentAttributes.html)
