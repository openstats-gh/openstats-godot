class_name AddProgressRequest extends OpenstatsRequest

signal completed(progress: Dictionary[String, int])

var _game_session_token: String
var _user_rid: String
var _game_rid: String
var _progress: Dictionary[String, int]

func _get_url() -> String:
	return "%s/users/v1/%s/games/%s/achievements" % [_api_url, _user_rid.uri_encode(), _game_rid.uri_encode()]

func _get_headers() -> PackedStringArray:
	return [
		"Authorization: Bearer " + _game_session_token,
		"Accept: application/json application/problem+json",
		"Accept-Charset: utf-8",
	]

func _get_method() -> HTTPClient.Method:
	return HTTPClient.METHOD_POST

func _get_body() -> String:
	return JSON.stringify({"progress": _progress})

func _verify() -> int:
	if _game_session_token == null or _game_session_token.is_empty():
		return ERR_INVALID_DATA

	if _user_rid == null or _user_rid.is_empty():
		return ERR_INVALID_DATA

	if _game_rid == null or _game_rid.is_empty():
		return ERR_INVALID_DATA

	return super._verify()

func _completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var progress_floats: Dictionary = _json.data.progress
	var progress_ints: Dictionary[String, int] = {}
	for slug in progress_floats:
		progress_ints[slug] = int(progress_floats[slug])
	completed.emit(progress_ints)
	return true
