extends Node
## TODO: document Openstats!

## game_rid must be set before calling start_session, with the RID of the Game registered in openstats
var game_rid: String
## game_token must be set before calling start_session, with the Game Token provided by the player
var game_token: String
# var api_url: String = "https://openstats.social/api/"
var api_url: String = "http://localhost:3000"

var user_rid: String

var session_ready: bool:
	get:
		return _session_ready

signal session_failed(error: Error, response_code: int, details: ProblemDetails)
signal session_started(session: OpenstatsModels.GameSession)

signal heartbeat_failed(error: Error, response_code: int, details: ProblemDetails)
signal heartbeat_completed(session: OpenstatsModels.GameSession)

const REQUEST_POOL_SIZE = 8
var _request_pool: Array[HTTPRequest] = []
var _request_work_queue: Array[Callable] = []

var _json: JSON = JSON.new()
var _session_mutex: Mutex = Mutex.new()
var _session: OpenstatsModels.GameSession
var _heartbeat_mutex: Mutex = Mutex.new()
var _heartbeat_timer: Timer

var _jwt: String
var _session_id: String
var _session_ready: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

	_request_pool.resize(REQUEST_POOL_SIZE)
	for idx in REQUEST_POOL_SIZE:
		var request := HTTPRequest.new()
		request.timeout = 10
		_request_pool[idx] = request
		add_child(request)

func _queue_request(request: OpenstatsRequest):
	var wrapped_work: Callable = func(http_request: HTTPRequest):
		request._run(http_request)
		await http_request.request_completed
		_mark_request_available(http_request)

	var next_worker: HTTPRequest = _request_pool.pop_front()
	if next_worker != null:
		wrapped_work.call(next_worker)
		return
	
	_request_work_queue.push_back(wrapped_work)

func _mark_request_available(http_request: HTTPRequest):
	var next_work = _request_work_queue.pop_front()
	if next_work != null:
		next_work.call(http_request)
		return

	_request_pool.push_back(http_request)

func _start_session_url(user_rid: String, game_rid: String) -> String:
	return "%/users/v1/%/games/%/sessions" % [api_url, user_rid.uri_encode(), game_rid.uri_encode()]

func _heartbeat_url(user_rid: String, game_rid: String, session_rid: String) -> String:
	return "%/users/v1/%/games/%/sessions/%" % [
		api_url,
		user_rid.uri_encode(),
		game_rid.uri_encode(),
		session_rid.uri_encode()
	]

func _achievements_url(user_rid: String, game_rid: String) -> String:
	return "%/users/v1/%/games/%/achievements"

## Spawns an asynchronous request to create a new Game Session.
## 
## Returns [constant ERR_INVALID_DATA] if game_rid or game_token aren't provided;
## [constant ERR_ALREADY_IN_USE] if a session has already been started, or there is an
## ongoing request to start a session.[br][br]
## 
## Creates a [annotation HTTPRequest] and sends a request to openstats to create a new Game Session, 
## and  returns [constant OK]. If the request successfully creates a Game Session, emits 
## [signal session_started]; otherwise, emits [signal session_failed] with information about the 
## failure.
##
## Upon success, creates a [annotation Timer] that periodically pulses the Game Session to keep it 
## alive.
func start_session() -> int:
	if !_session_mutex.try_lock():
		return ERR_ALREADY_IN_USE

	var session_request := _create_session()
	session_request.completed.connect(_on_session_request_completed, CONNECT_ONE_SHOT)
	session_request.errored.connect(_on_session_request_errored, CONNECT_ONE_SHOT)

	var error := session_request.run()
	if error != OK:
		_session_mutex.unlock()
		return error

	return OK

func _on_session_request_completed(session: OpenstatsModels.GameSession, session_token: String):
	_session = session
	_jwt = session_token

	_heartbeat_timer = Timer.new()
	_heartbeat_timer.timeout.connect(_on_heartbeat_timeout)
	_heartbeat_timer.one_shot = true
	add_child(_heartbeat_timer)

	_heartbeat_timer.start(_session.next_pulse_after)
	_session_ready = true
	session_started.emit(_session)

func _on_session_request_errored(error: Error, response_code: int, details: ProblemDetails):
	_session_mutex.unlock()
	session_failed.emit(error, response_code, details)

func _on_heartbeat_timeout():
	if !_session_ready:
		return

	var heartbeat_request := _heartbeat()

	heartbeat_request.completed.connect(_on_heartbeat_request_completed, CONNECT_ONE_SHOT)
	heartbeat_request.errored.connect(_on_heartbeat_request_errored, CONNECT_ONE_SHOT)

	var error := heartbeat_request.run()
	if error != OK:
		heartbeat_failed.emit(error, 0, null)
		return

func _on_heartbeat_request_completed(session: OpenstatsModels.GameSession, session_token: String):
	_session = session
	if session_token:
		_jwt = session_token

	_heartbeat_timer.start(_session.next_pulse_after)
	heartbeat_completed.emit(_session)

func _on_heartbeat_request_errored(error: Error, response_code: int, details: ProblemDetails):
	heartbeat_failed.emit(error, response_code, details)

func _create_session() -> CreateSessionRequest:
	var request := CreateSessionRequest.new()
	request._api_url = api_url
	request._game_token = game_token
	request._user_rid = user_rid
	request._game_rid = game_rid
	request._queue_work = _queue_request
	return request

func _heartbeat() -> HeartbeatRequest:
	var request = HeartbeatRequest.new()
	request._api_url = api_url
	request._game_session_token = _jwt
	request._user_rid = user_rid
	request._game_rid = game_rid
	request._session_rid = _session.rid
	request._queue_work = _queue_request
	return request

func get_user(rid: String = "@me") -> GetUserRequest:
	var request := GetUserRequest.new()
	request._api_url = api_url
	request._game_token = game_token
	request._user_rid = rid
	request._queue_work = _queue_request
	return request

func get_achievement_progress(user_rid: String) -> GetProgressRequest:
	if !_jwt || !api_url || !game_rid || !user_rid:
		return null

	var request := GetProgressRequest.new()
	request._api_url = api_url
	request._game_session_token = _jwt
	request._user_rid = user_rid
	request._game_rid = game_rid
	request._queue_work = _queue_request
	return request

## Creates and sends a request to add achievement progress for the Game Session's User. Returns an 
## [annotation AddProgressRequest] with an in-progress request.[br][br]
## 
## If [member session_ready] is false, then it doesn't start a request, and will return [code]null[/code].[br][br]
##
## To handle the request, you should immediately connect to [signal AddProgressRequest.completed]. 
## Optionally connect to [signal AddProgressRequest.errored] to handle errors.
func add_achievement_progress(progress: Dictionary[String, int]) -> AddProgressRequest:
	if !session_ready || !_jwt || !api_url || !game_rid || !user_rid || progress.is_empty():
		return null

	var request := AddProgressRequest.new()
	request._api_url = api_url
	request._game_session_token = _jwt
	request._user_rid = user_rid
	request._game_rid = game_rid
	request._progress = progress
	request._queue_work = _queue_request
	return request

class CreateSessionRequest extends OpenstatsRequest:
	signal completed(session: OpenstatsModels.GameSession, session_token: String)

	var _game_token: String
	var _user_rid: String
	var _game_rid: String

	func _get_url() -> String:
		return "%s/users/v1/%s/games/%s/sessions" % [_api_url, _user_rid.uri_encode(), _game_rid.uri_encode()]

	func _get_headers() -> PackedStringArray:
		return [
			"Authorization: Bearer " + _game_token,
			"Accept: application/json application/problem+json",
			"Accept-Charset: utf-8",
		]

	func _get_method() -> HTTPClient.Method:
		return HTTPClient.METHOD_POST

	func _verify() -> int:
		if _game_token == null or _game_token.is_empty():
			return ERR_INVALID_DATA

		if _user_rid == null or _user_rid.is_empty():
			return ERR_INVALID_DATA

		if _game_rid == null or _game_rid.is_empty():
			return ERR_INVALID_DATA

		return super._verify()

	func _completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		var session_token := ""
		for header in headers:
			const token_header_name = "X-Game-Session-Token: "
			if header.begins_with(token_header_name):
				session_token = header.substr(len(token_header_name)).strip_edges()

		completed.emit(OpenstatsModels.GameSession.from(_json.data), session_token)

class HeartbeatRequest extends OpenstatsRequest:
	signal completed(session: OpenstatsModels.GameSession, session_token: String)

	var _game_session_token: String
	var _user_rid: String
	var _game_rid: String
	var _session_rid: String

	func _get_url() -> String:
		return "%s/users/v1/%s/games/%s/sessions/%s/heartbeat" % [_api_url, _user_rid.uri_encode(), _game_rid.uri_encode(), _session_rid.uri_encode()]

	func _get_headers() -> PackedStringArray:
		return [
			"Authorization: Bearer " + _game_session_token,
			"Accept: application/json application/problem+json",
			"Accept-Charset: utf-8",
		]

	func _get_method() -> HTTPClient.Method:
		return HTTPClient.METHOD_POST

	func _verify() -> int:
		if _game_session_token == null or _game_session_token.is_empty():
			return ERR_INVALID_DATA

		if _user_rid == null or _user_rid.is_empty():
			return ERR_INVALID_DATA

		if _game_rid == null or _game_rid.is_empty():
			return ERR_INVALID_DATA

		if _session_rid == null or _session_rid.is_empty():
			return ERR_INVALID_DATA

		return super._verify()

	func _completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		var session_token := ""
		for header in headers:
			const token_header_name = "X-Game-Session-Token: "
			if header.begins_with(token_header_name):
				session_token = header.substr(len(token_header_name)).strip_edges()

		completed.emit(OpenstatsModels.GameSession.from(_json.data), session_token)
