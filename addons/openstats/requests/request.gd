class_name OpenstatsRequest extends RefCounted

signal errored(error: Error, response_code: int, details: ProblemDetails)

var _queue_work: Callable
var _json: JSON = JSON.new()
var _api_url: String

func _get_url() -> String:
	return _api_url

func _get_headers() -> PackedStringArray:
	return [
		"Accept: application/json application/problem+json",
		"Accept-Charset: utf-8"
	]

func _get_method() -> HTTPClient.Method:
	return HTTPClient.METHOD_GET

func _get_body() -> String:
	return ""

func _verify() -> int:
	if _api_url == null or _api_url.is_empty():
		return ERR_INVALID_DATA

	return OK
	
func _completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	pass

func _base_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var body_json = body.get_string_from_utf8()
	var err = _json.parse(body_json)
	if err != OK:
		errored.emit(err, response_code, null)
		return

	if typeof(_json.data) != TYPE_DICTIONARY:
		errored.emit(ERR_INVALID_DATA, response_code, null)
		return

	if response_code != 200:
		var problem_details = ProblemDetails.from(_json.data)
		errored.emit(FAILED, response_code, problem_details)
		return
	
	_completed(result, response_code, headers, body)

func _run(http_request: HTTPRequest) -> void:
	var url := _get_url()
	var headers := _get_headers()

	var connect_err := http_request.request_completed.connect(_base_completed)
	if connect_err != OK:
		errored.emit(connect_err, 0, null)
		return

	var err := http_request.request(url, headers, _get_method(), _get_body())
	if err != OK:
		errored.emit(err, 0, null)
		return

func run() -> Error:
	var error := _verify()
	if error != OK:
		return error

	_queue_work.call(self)
	return OK
