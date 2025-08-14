class_name GetUserRequest extends OpenstatsRequest

#class User:
	#var rid: String
	#var slug: String
	#var display_name: String
	#var created_at: String
#
	#static func from(data: Dictionary) -> User:
		#var user := User.new()
		#user.rid = data.rid
		#user.slug = data.slug
		#user.display_name = data.displayName
		#user.created_at = data.createdAt
		#return user

signal completed(user: OpenstatsModels.User)

var _game_token: String
var _user_rid: String

func _get_url() -> String:
	return "%s/users/v1/%s" % [_api_url, _user_rid.uri_encode()]

func _get_headers() -> PackedStringArray:
	return [
		"Authorization: Bearer " + _game_token,
		"Accept: application/json application/problem+json",
		"Accept-Charset: utf-8",
	]

func _verify() -> int:
	if _game_token == null or _game_token.is_empty():
		return ERR_INVALID_DATA

	if _user_rid == null or _user_rid.is_empty():
		return ERR_INVALID_DATA

	return super._verify()

func _completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var user := OpenstatsModels.User.from(_json.data)
	completed.emit(user)
	return true
