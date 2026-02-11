# Common Feature Design Patterns

Production-proven patterns for implementing common Rails features. Each follows the core principles: REST resources, domain methods, event tracking, smart defaults.

## Adding "Starring" to a Resource

```ruby
# Migration
create_table :stars do |t|
  t.uuid :card_id, null: false
  t.uuid :user_id, null: false
  t.timestamps

  t.index [:card_id, :user_id], unique: true
end

# Model concern
module Card::Starrable
  def star(user: Current.user)
    stars.create!(user: user)
    track_event :starred, creator: user
  end

  def starred_by?(user)
    stars.exists?(user: user)
  end
end

# Controller
class Cards::StarsController < ApplicationController
  def create
    @card.star
  end

  def destroy
    @card.unstar
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

```ruby
# Model concern
module Searchable
  extend ActiveSupport::Concern

  included do
    after_commit :index_for_search, if: :should_index?
  end

  def index_for_search
    Search::Record.for(account_id).upsert(
      searchable_id: id,
      content: searchable_content
    )
  end
end
```

## Adding Notifications

```ruby
# Model
class Notification < ApplicationRecord
  belongs_to :event
  belongs_to :recipient, class_name: "User"

  enum state: { unread: 0, read: 1 }
end

# Event callback
after_create_commit :create_notifications

def create_notifications
  recipients.each do |user|
    Notification.create!(event: self, recipient: user)
  end
end
```
