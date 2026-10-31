# Common Feature Design Patterns

Production-proven patterns for implementing common Rails features. Each follows the core principles: REST resources, domain methods, event tracking, smart defaults.

## Contents

- [Adding "Starring" to a Resource](#adding-starring-to-a-resource)
- [Adding Comments](#adding-comments)
- [Adding Search](#adding-search)
- [Adding Notifications](#adding-notifications)

## Adding "Starring" to a Resource

Both verbs are idempotent, and neither tracks an event: per-user state isn't
activity. If you do want one, guard it on the actual change and wrap it in a
`transaction`.

```ruby
# Migration
create_table :stars, id: :string do |t|
  t.references :card, type: :string, null: false, foreign_key: true
  t.references :user, type: :string, null: false, foreign_key: true
  t.timestamps

  t.index %i[ card_id user_id ], unique: true
end

# Model concern
module Card::Starrable
  extend ActiveSupport::Concern

  included do
    has_many :stars, dependent: :destroy
  end

  def star_by(user)
    stars.find_or_create_by!(user: user)
  end

  def unstar_by(user)
    stars.destroy_by(user: user)
  end

  def starred_by?(user)
    stars.exists?(user: user)
  end
end

# Controller
class Cards::StarsController < ApplicationController
  include CardScoped

  def create
    @card.star_by Current.user
  end

  def destroy
    @card.unstar_by Current.user
  end
end

# Routes
resources :cards do
  resource :star
end
```

## Adding Comments

```ruby
# Model
class Comment < ApplicationRecord
  belongs_to :card
  belongs_to :creator, class_name: "User", default: -> { Current.user }

  include Eventable
  after_create_commit -> { track_event :created }
end

# Controller
class Cards::CommentsController < ApplicationController
  def create
    @comment = @card.comments.create!(comment_params)
  end
end
```

## Adding Search

An integer-keyed `search_records` table indexed by FTS5 in external-content
mode — see `docs/sqlite-extensions-and-features.md` for the virtual table and
its sync triggers. Models upsert their row from commit callbacks, which reach
rich text in `action_text_rich_texts` that triggers can't see. Each row carries
`account_id` and the access-scope key, so a search authorizes without a join.

```ruby
# Migration (plus search_records_fts and its triggers)
create_table :search_records do |t|   # integer key on purpose: it becomes the FTS5 rowid
  t.string :searchable_type, null: false
  t.string :searchable_id, null: false
  t.string :account_id, null: false, index: true
  t.string :board_id, null: false
  t.text :content
  t.index [:searchable_type, :searchable_id], unique: true
end

# Model concern
module Searchable
  extend ActiveSupport::Concern

  included do
    after_save_commit :reindex
    after_destroy_commit :remove_from_search
  end

  private
    def reindex
      SearchRecord.upsert(
        { searchable_type: self.class.name, searchable_id: id,
          account_id: account_id, board_id: board_id, content: search_content },
        unique_by: [:searchable_type, :searchable_id])
    end

    def remove_from_search
      SearchRecord.where(searchable_type: self.class.name, searchable_id: id).delete_all
    end
end

# Query: filter every search on the tenant and the user's accessible scope
SearchRecord.joins("JOIN search_records_fts ON search_records_fts.rowid = search_records.id")
  .where("search_records_fts MATCH ?", query)
  .where(account_id: Current.account.id, board_id: Current.user.board_ids)
  .order(Arel.sql("bm25(search_records_fts)"))

# Account: clear its rows before it goes
before_destroy { SearchRecord.where(account_id: id).delete_all }
```

`MATCH` parses FTS5 query syntax, so quote user input as a phrase; a stray `"`
raises `ActiveRecord::StatementInvalid`.

## Adding Notifications

Fan out in a job, dedupe on a unique index, and record read state as a
timestamp.

```ruby
# Migration
create_table :notifications, id: :string do |t|
  t.references :source, type: :string, polymorphic: true, null: false
  t.references :recipient, type: :string, null: false, foreign_key: { to_table: :users }
  t.datetime :read_at
  t.timestamps

  t.index %i[ recipient_id source_type source_id ], unique: true
end

# Model
class Notification < ApplicationRecord
  belongs_to :source, polymorphic: true
  belongs_to :recipient, class_name: "User"

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }

  def read
    update!(read_at: Time.current)
  end

  def unread
    update!(read_at: nil)
  end
end

# Source concern
module Notifiable
  extend ActiveSupport::Concern

  included do
    after_create_commit :notify_recipients_later
  end

  def notify_recipients
    Notifier.for(self).notify
  end

  private
    def notify_recipients_later
      NotifyRecipientsJob.perform_later(self)
    end
end

# Per-source recipient rules
class Notifier
  def self.for(source)
    "#{source.class}Notifier".constantize.new(source)
  end

  def initialize(source)
    @source = source
  end

  def notify
    # One order everywhere, so concurrent runs can't deadlock
    recipients.sort_by(&:id).each do |user|
      Notification.create_or_find_by!(source: @source, recipient: user)
    end
  end
end

class CommentNotifier < Notifier
  private
    def recipients
      @source.card.watchers.excluding(@source.creator)
    end
end
```
