extends Node2D

@onready var game_rid: Label = $Control/VBoxContainer/HBoxContainer/GameRIDLabel
@onready var game_token_edit: LineEdit = $Control/VBoxContainer/HBoxContainer/GameTokenTextEdit
@onready var begin_session_button: Button = $Control/VBoxContainer/HBoxContainer/BeginSessionButton

@onready var user_rid: Label = $Control/VBoxContainer/SessionInfo/UserRID
@onready var user_slug: Label = $Control/VBoxContainer/SessionInfo/UserSlug
@onready var session_rid: Label = $Control/VBoxContainer/SessionInfo/SessionRID
@onready var last_pulse_time: Label = $Control/VBoxContainer/SessionInfo/LastPulseTime
@onready var next_pulse_time: Label = $Control/VBoxContainer/SessionInfo/NextPulseTime

@onready var get_progress: Button = $Control/VBoxContainer/HBoxContainer2/GetProgressButton
@onready var add_progress: Button = $Control/VBoxContainer/HBoxContainer2/AddProgressButton

@onready var ach1_current_progress: Label = $Control/VBoxContainer/Achievement1/CurrentProgress
@onready var ach2_current_progress: Label = $Control/VBoxContainer/Achievement2/CurrentProgress
@onready var ach3_current_progress: Label = $Control/VBoxContainer/Achievement3/CurrentProgress

@onready var ach1_add_progress: CheckBox = $Control/VBoxContainer/Achievement1/AddProgressCheckBox
@onready var ach2_add_progress: CheckBox = $Control/VBoxContainer/Achievement2/AddProgressCheckBox
@onready var ach3_add_progress: CheckBox = $Control/VBoxContainer/Achievement3/AddProgressCheckBox

@onready var ach1_new_progress: SpinBox = $Control/VBoxContainer/Achievement1/AddProgressValueBox
@onready var ach2_new_progress: SpinBox = $Control/VBoxContainer/Achievement2/AddProgressValueBox
@onready var ach3_new_progress: SpinBox = $Control/VBoxContainer/Achievement3/AddProgressValueBox

const ach1_slug = "test-ach-1"
const ach2_slug = "test-ach-2"
const ach3_slug = "test-ach-3"

var _user: OpenstatsModels.User
var _session: OpenstatsModels.GameSession

func _ready():
	# test-game RID
	Openstats.game_rid = "g_30JsWkn0GHof1LXH62Idm"
	game_rid.text = Openstats.game_rid
	Openstats.session_failed.connect(_on_session_failed)
	Openstats.session_started.connect(_on_session_started)
	Openstats.heartbeat_failed.connect(_on_heartbeat_failed)
	Openstats.heartbeat_completed.connect(_on_heartbeat_completed)

func _on_begin_session_button_pressed() -> void:
	game_token_edit.editable = false
	begin_session_button.disabled = true

	Openstats.game_token = game_token_edit.text

	# we need the User's RID before we can start the session
	var user_request := Openstats.get_user()
	user_request.errored.connect(_on_user_request_errored, CONNECT_ONE_SHOT)
	user_request.completed.connect(_on_user_request_completed, CONNECT_ONE_SHOT)

	var error := user_request.run()
	if error != OK:
		game_token_edit.editable = true
		begin_session_button.disabled = false
		push_error("Error getting user info: ", error_string(user_request.error))

func _on_user_request_errored(error: Error, response_code: int, details: ProblemDetails):
	game_token_edit.editable = true
	begin_session_button.disabled = false
	push_error("User info request failed: ", error_string(error), response_code, details)

func _on_user_request_completed(user: OpenstatsModels.User):
	user_rid.text = user.rid
	user_slug.text = user.slug
	Openstats.user_rid = user.rid
	_user = user

	var error := Openstats.start_session()
	if error != OK:
		game_token_edit.editable = true
		begin_session_button.disabled = false
		push_error("Error starting game session: ", error_string(error))

func _disable_achievement_inputs() -> void:
	get_progress.disabled = true
	add_progress.disabled = true

	ach1_add_progress.disabled = true
	ach2_add_progress.disabled = true
	ach3_add_progress.disabled = true

	ach1_new_progress.editable = false
	ach2_new_progress.editable = false
	ach3_new_progress.editable = false

func _enable_achievement_inputs() -> void:
	get_progress.disabled = false
	add_progress.disabled = false

	ach1_add_progress.disabled = false
	ach2_add_progress.disabled = false
	ach3_add_progress.disabled = false

	ach1_new_progress.editable = true
	ach2_new_progress.editable = true
	ach3_new_progress.editable = true

func _on_get_progress_button_pressed() -> void:
	if !Openstats.session_ready:
		return

	# temporarily disabling the achievement inputs so we don't send multiple requests
	_disable_achievement_inputs()

	var progress_request := Openstats.get_achievement_progress(Openstats.user_rid)
	
	progress_request.completed.connect(
		func(progress: Dictionary[String, int]):
			for slug in progress:
				match slug:
					ach1_slug:
						ach1_current_progress.text = str(progress[slug])
					ach2_slug:
						ach2_current_progress.text = str(progress[slug])
					ach3_slug:
						ach3_current_progress.text = str(progress[slug])
			
			_enable_achievement_inputs()
	, CONNECT_ONE_SHOT)

	progress_request.errored.connect(
		func(err: Error, response_code: int, details: ProblemDetails):
			push_error("Failed to get achievement progress: ", error_string(err), response_code, details)
	, CONNECT_ONE_SHOT)

	var error := progress_request.run()
	if error != OK:
		_enable_achievement_inputs()
		push_error("Error getting achievement progress: ", error_string(error))
		return

func _on_add_progress_button_pressed() -> void:
	if !Openstats.session_ready:
		return

	# temporarily disabling the achievement inputs so we don't send multiple requests
	_disable_achievement_inputs()
	
	var new_progress: Dictionary[String, int] = {}
	if ach1_add_progress.button_pressed:
		new_progress[ach1_slug] = int(ach1_new_progress.value)

	if ach2_add_progress.button_pressed:
		new_progress[ach2_slug] = int(ach2_new_progress.value)

	if ach3_add_progress.button_pressed:
		new_progress[ach3_slug] = int(ach3_new_progress.value)

	var progress_request := Openstats.add_achievement_progress(new_progress)
	
	progress_request.completed.connect(
		func(progress: Dictionary[String, int]):
			for slug in new_progress:
				if slug not in progress:
					push_warning("We sent '%s: %d' but the response didn't contain that slug. This usually means that the progress we sent was below the user's current progress, or was greater than the progress requirement for that achievement, which is a no-op." % [slug, new_progress[slug]])
					continue
				match slug:
					ach1_slug:
						ach1_current_progress.text = str(progress[slug])
					ach2_slug:
						ach2_current_progress.text = str(progress[slug])
					ach3_slug:
						ach3_current_progress.text = str(progress[slug])
			
			_enable_achievement_inputs()
	, CONNECT_ONE_SHOT)

	progress_request.errored.connect(
		func(err: Error, response_code: int, details: ProblemDetails):
			push_error("Failed to add achievement progress: ", error_string(err), response_code, details)
	, CONNECT_ONE_SHOT)

	var error := progress_request.run()
	if error != OK:
		_enable_achievement_inputs()
		push_error("Error adding achievement progress: ", error_string(error))

func _on_session_failed(error: Error, response_code: int, details: ProblemDetails):
	game_token_edit.editable = true
	begin_session_button.disabled = false
	push_error("Session failed to start: ", error_string(error), response_code, details)

func _on_session_started(session: OpenstatsModels.GameSession):
	_enable_achievement_inputs()
	
	_session = session
	_update_session()

func _on_heartbeat_failed(error: Error, response_code: int, details: ProblemDetails):
	push_error("Session failed to heartbeat: ", error_string(error), response_code, details)

func _on_heartbeat_completed(session: OpenstatsModels.GameSession):
	_session = session
	_update_session()

func _update_session():
	user_rid.text = _session.user.rid
	user_slug.text = _session.user.slug
	session_rid.text = _session.rid

	var time_zone_bias_seconds: int = Time.get_time_zone_from_system().bias * 60
	# the API always returns unix time in milliseconds
	var last_pulse_in_seconds := _session.last_pulse.substr(0, len(_session.last_pulse) - 3)
	var last_pulse_unix: int = int(last_pulse_in_seconds) + time_zone_bias_seconds
	var last_pulse_dict := Time.get_datetime_dict_from_unix_time(last_pulse_unix)
	last_pulse_time.text = "%02d:%02d:%02d" % [last_pulse_dict.hour, last_pulse_dict.minute, last_pulse_dict.second]

	var next_pulse_dict := Time.get_datetime_dict_from_unix_time(last_pulse_unix + _session.next_pulse_after)
	next_pulse_time.text = "%02d:%02d:%02d" % [next_pulse_dict.hour, next_pulse_dict.minute, next_pulse_dict.second]
