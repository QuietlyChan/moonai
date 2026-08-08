///|
fn minimax_optional_string_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(String(_)) => true
    _ => false
  }
}

///|
fn minimax_optional_number_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(Number(_)) => true
    _ => false
  }
}

///|
fn minimax_create_video_response_validation_error(json : Json) -> String? {
  guard json is Object(fields) else {
    return Some("MiniMax create-video response must be a JSON object")
  }
  if !minimax_optional_string_field_is_valid(fields, "task_id") {
    return Some(
      "MiniMax create-video response task_id must be a string or null",
    )
  }
  None
}

///|
fn validate_minimax_create_video_response(json : Json) -> Unit raise {
  if minimax_create_video_response_validation_error(json) is Some(error) {
    raise @provider.InvalidResponseDataError(message=error, data=json)
  }
}

///|
fn minimax_video_content_validation_error(value : Json?) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) =>
      if minimax_optional_string_field_is_valid(fields, "url") {
        None
      } else {
        Some("MiniMax video status task.content.url must be a string or null")
      }
    _ => Some("MiniMax video status task.content must be an object or null")
  }
}

///|
fn minimax_video_usage_validation_error(value : Json?) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      for name in ["total_seconds", "input_seconds", "output_seconds"] {
        if !minimax_optional_number_field_is_valid(fields, name) {
          return Some(
            "MiniMax video status task.usage.\{name} must be a number or null",
          )
        }
      }
      None
    }
    _ => Some("MiniMax video status task.usage must be an object or null")
  }
}

///|
fn minimax_video_task_error_validation_error(value : Json?) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      match fields.get("code") {
        None | Some(Null) | Some(String(_)) | Some(Number(_)) => ()
        _ =>
          return Some(
            "MiniMax video status task.error.code must be a string, number, or null",
          )
      }
      if !minimax_optional_string_field_is_valid(fields, "message") {
        return Some(
          "MiniMax video status task.error.message must be a string or null",
        )
      }
      None
    }
    _ => Some("MiniMax video status task.error must be an object or null")
  }
}

///|
fn minimax_video_status_response_validation_error(json : Json) -> String? {
  guard json is Object(fields) else {
    return Some("MiniMax video status response must be a JSON object")
  }
  guard fields.get("task") is Some(Object(task)) else {
    return Some("MiniMax video status response task must be an object")
  }
  for name in ["id", "status", "resolution", "ratio"] {
    if !minimax_optional_string_field_is_valid(task, name) {
      return Some("MiniMax video status task.\{name} must be a string or null")
    }
  }
  if !minimax_optional_number_field_is_valid(task, "duration") {
    return Some("MiniMax video status task.duration must be a number or null")
  }
  if minimax_video_content_validation_error(task.get("content")) is Some(error) {
    return Some(error)
  }
  if minimax_video_usage_validation_error(task.get("usage")) is Some(error) {
    return Some(error)
  }
  minimax_video_task_error_validation_error(task.get("error"))
}

///|
fn validate_minimax_video_status_response(json : Json) -> Unit raise {
  if minimax_video_status_response_validation_error(json) is Some(error) {
    raise @provider.InvalidResponseDataError(message=error, data=json)
  }
}
