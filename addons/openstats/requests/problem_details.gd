class_name ProblemDetails extends RefCounted

class ErrorDetail:
	var location: String
	var message: String
	var value: Variant

	static func from(data: Dictionary) -> ErrorDetail:
		var detail = ErrorDetail.new()
		detail.location = data.location
		detail.message = data.message
		detail.value = data.value
		return detail

var title: String
var detail: String
var type: String
var errors: Array[ErrorDetail]
var instance: String
var status: int

static func from(data: Dictionary) -> ProblemDetails:
	var details = ProblemDetails.new()
	details.title = data.title
	details.detail = data.detail
	details.type = data.type
	details.instance = data.instance
	details.status = data.status

	if typeof(data.errors) == TYPE_ARRAY:
		details.errors = []
		for error in data.errors as Array[Dictionary]:
			details.errors.push_back(ErrorDetail.from(error))

	return details
