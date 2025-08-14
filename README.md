# openstats-godot
openstats SDK for Godot Engine 4

## Installing

1. Download the latest release
2. Extract the `addons` folder into your Godot project.
3. Add `addons/openstats/openstats.gd` as a Global Autoload to your project

> [!IMPORTANT]
> The instructions below assume you've named your Autoload `Openstats`. If you name it something else, keep that in 
> mind as you read along.

## Getting started

Check out [example.gd](example/example.gd) for working example usage. Otherwise, follow along below.

### Setting the player's Game token

Openstats provides a session-based API, which requires a "Game Token". The Game Token is essentially a password that 
allows your game to create "Game Sessions", which are used to track stats, playtime, and achievements on the player's 
behalf.

You should instruct the player to create a new Game Token for your game on their favourite openstats instance. Once the
player provides you with the Game Token, configure the Openstats singleton with the token:

```go
func _on_openstats_game_token_text_changed(new_text: String) -> void:
    Openstats.game_token = new_text
```

### Getting the player's User RID

The SDK will handle the bulk of the work creating a new Game Session. In order to create a new Session, you'll need to
know the user's RID. You can get this by calling `Openstats.get_user()` with no parameters, which creates an openstats
query for some information about the user associated with `game_token`.

> [!NOTE]
> Openstats RID's are not the same thing as Godot's RID. Openstats RID's are a type safe unique identifier. Every
> resource has them - such as Users, Games, Achievements, and Game Sessions.

```go
func _get_user_rid() -> void:
    var user_query := Openstats.get_user()
    user_query.completed.connect(_on_user_query_completed)
    user_query.run()

func _on_user_query_completed(user: OpenstatsModels.User) -> void:
    Openstats.user_rid = user.rid
    # ...
```

> [!IMPORTANT]
> `user_query.run()` will add the query to a queue, which will execute the query asynchronously as soon as possible.
> The query isn't necessarily finished after `run()` has returned. Instead, the `completed` signal will be emitted once
> the query completes successfully.

> [!NOTE]
> all queries like this also have an `errored` signal you can connect to if you want to handle errors

### Starting the Game Session

Before starting the session, you should connect to `Openstats.session_started` and `Openstats.heartbeat_completed`:

```go
func _ready():
    Openstats.session_started.connect(_on_session_started)
    Openstats.heartbeat_completed.connect(_on_heartbeat_completed)

func _on_session_started(session: OpenstatsModels.GameSession):
    # the session was created successfully, `session` contains information 
    # about the new session

func _on_heartbeat_completed(session: OpenstatsModels.GameSession):
	# the session heartbeat completed successfully, `session` contains the
    # latest session information
```

> [!NOTE]
> theres also `session_failed` and `heartbeat_failed` signals if you want to handle errors

After setting `Openstats.user_rid`, initialize a new Session:

```go
func _on_user_query_completed(user: OpenstatsModels.User) -> void:
    Openstats.user_rid = user.rid
    Openstats.start_session()
```

Once the connection is complete, `session_started` will get emitted. `Openstats.start_session()` also creates a timer
that periodically sends a heartbeat pulse to the openstats API, which is necessary to keep the Game Session alive. 
Every time the heartbeat completes succesfully, `heartbeat_completed` will get emitted.

### Getting the player's achievement progress

Openstats Achievements are assigned a unique human-readable "Slug" by the developer, and are configured with a 
"Progress Requirement". Progress requirements are an integer greater than 0 that indicates how much "progress" a user
must have in order to have acquired the achievement.

`Openstats.get_achievement_progress`, given some user's RID, creates a query that returns that user's achievement 
progress, as a dictionary that maps Achievement Slugs to progress integers. Progress is only returned for achievements
of the game associated with the current game session, that the player also has progress in.

As an example, to get the current user's achievement progress:

```go
func _get_achievement_progress() -> void:
    var progress_query := Openstats.get_achievement_progress(Openstats.user_rid)
    progress_query.completed.connect(_on_get_progress_query_completed)
    progress_query.run()

func _on_get_progress_query_completed(new_progress: Dictionary[String, int]) -> void:
    for slug in new_progress:
        var value := new_progress[slug]
        # do something with `slug` and `value`
```

### Adding achievement progress

`Openstats.add_achievement_progress`, given a dictionary that maps achievement slugs to progress ints, creates a query 
that updates the user's progress of the achievements in the progress dictionary, to the mapped values. The response
will contain the progress values.

> [!NOTE]
> - If the provided progress value is lower than the user's current progress for that achievement, then it will be
> ignored.
> - If the provided progress value is higher than the achievement's progress requirement, then it will be ignored.

To update the current user's progress for some achievements:

```gdscript
var new_progress: Dictionary[String, int] = {
    # some achievements are basically just flags, with a progress requirement of 1.
    "beat-the-game": 1,
    # others might have much higher progress requirements. This one might have a progress requirement of 100, but the
    # player has only defeated 62 of the 100 required foes to get this achievement.
    "defeat-lots-of-foes": 62,
}

var progress_query := Openstats.add_achievement_progress(new_progress)
progress_query.completed.connect(_on_set_progress_query_completed)
progress_query.run()
```