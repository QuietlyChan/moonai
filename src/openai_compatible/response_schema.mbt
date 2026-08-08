///|
fn compatible_optional_string_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(String(_)) => true
    _ => false
  }
}

///|
fn compatible_optional_number_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(Number(_)) => true
    _ => false
  }
}

///|
fn compatible_usage_details_validation_error(
  value : Json?,
  path : String,
  fields_to_validate : Array[String],
) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      for name in fields_to_validate {
        if !compatible_optional_number_field_is_valid(fields, name) {
          return Some("\{path}.\{name} must be a number or null")
        }
      }
      None
    }
    _ => Some("\{path} must be an object or null")
  }
}

///|
fn compatible_usage_validation_error(value : Json?, path : String) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      for name in ["prompt_tokens", "completion_tokens", "total_tokens"] {
        if !compatible_optional_number_field_is_valid(fields, name) {
          return Some("\{path}.\{name} must be a number or null")
        }
      }
      if compatible_usage_details_validation_error(
          fields.get("prompt_tokens_details"),
          path + ".prompt_tokens_details",
          ["cached_tokens", "cache_creation_input_tokens"],
        )
        is Some(error) {
        return Some(error)
      }
      compatible_usage_details_validation_error(
        fields.get("completion_tokens_details"),
        path + ".completion_tokens_details",
        [
          "reasoning_tokens", "accepted_prediction_tokens", "rejected_prediction_tokens",
        ],
      )
    }
    _ => Some("\{path} must be an object or null")
  }
}

///|
fn compatible_thought_signature_validation_error(
  value : Json?,
  path : String,
) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(extra)) =>
      match extra.get("google") {
        None | Some(Null) => None
        Some(Object(google)) =>
          if compatible_optional_string_field_is_valid(
              google, "thought_signature",
            ) {
            None
          } else {
            Some("\{path}.google.thought_signature must be a string or null")
          }
        _ => Some("\{path}.google must be an object or null")
      }
    _ => Some("\{path} must be an object or null")
  }
}

///|
fn compatible_response_tool_call_validation_error(
  value : Json,
  path : String,
) -> String? {
  guard value is Object(fields) else {
    return Some("\{path} must be an object")
  }
  if !compatible_optional_string_field_is_valid(fields, "id") {
    return Some("\{path}.id must be a string or null")
  }
  guard fields.get("function") is Some(Object(function)) else {
    return Some("\{path}.function must be an object")
  }
  guard function.get("name") is Some(String(_)) else {
    return Some("\{path}.function.name must be a string")
  }
  guard function.get("arguments") is Some(String(_)) else {
    return Some("\{path}.function.arguments must be a string")
  }
  compatible_thought_signature_validation_error(
    fields.get("extra_content"),
    path + ".extra_content",
  )
}

///|
fn compatible_response_message_validation_error(
  value : Json?,
  path : String,
) -> String? {
  guard value is Some(Object(fields)) else {
    return Some("\{path} must be an object")
  }
  match fields.get("role") {
    None | Some(Null) | Some(String("assistant")) => ()
    _ => return Some("\{path}.role must be assistant or null")
  }
  for name in ["content", "reasoning_content", "reasoning"] {
    if !compatible_optional_string_field_is_valid(fields, name) {
      return Some("\{path}.\{name} must be a string or null")
    }
  }
  match fields.get("tool_calls") {
    None | Some(Null) => None
    Some(Array(values)) => {
      for index, tool_call in values {
        if compatible_response_tool_call_validation_error(
            tool_call,
            path + ".tool_calls[" + index.to_string() + "]",
          )
          is Some(error) {
          return Some(error)
        }
      }
      None
    }
    _ => Some("\{path}.tool_calls must be an array or null")
  }
}

///|
/// Validate the limited response schema used by the AI SDK compatible chat
/// model. Unknown fields remain allowed for provider extensions.
pub fn validate_openai_compatible_chat_response(json : Json) -> String? {
  guard json is Object(fields) else {
    return Some("OpenAI-compatible response must be a JSON object")
  }
  if !compatible_optional_string_field_is_valid(fields, "id") ||
    !compatible_optional_string_field_is_valid(fields, "model") {
    return Some(
      "OpenAI-compatible response id and model must be strings or null",
    )
  }
  if !compatible_optional_number_field_is_valid(fields, "created") {
    return Some("OpenAI-compatible response created must be a number or null")
  }
  guard fields.get("choices") is Some(Array(choices)) else {
    return Some("OpenAI-compatible response must contain a choices array")
  }
  for index, choice in choices {
    guard choice is Object(choice_fields) else {
      return Some(
        "OpenAI-compatible response choices[" +
        index.to_string() +
        "] must be an object",
      )
    }
    if !compatible_optional_string_field_is_valid(
        choice_fields, "finish_reason",
      ) {
      return Some(
        "OpenAI-compatible response choices[" +
        index.to_string() +
        "].finish_reason must be a string or null",
      )
    }
    if compatible_response_message_validation_error(
        choice_fields.get("message"),
        "OpenAI-compatible response choices[" + index.to_string() + "].message",
      )
      is Some(error) {
      return Some(error)
    }
  }
  compatible_usage_validation_error(
    fields.get("usage"),
    "OpenAI-compatible response usage",
  )
}

///|
fn compatible_stream_tool_call_validation_error(
  value : Json,
  path : String,
) -> String? {
  guard value is Object(fields) else {
    return Some("\{path} must be an object")
  }
  if !compatible_optional_number_field_is_valid(fields, "index") {
    return Some("\{path}.index must be a number or null")
  }
  if !compatible_optional_string_field_is_valid(fields, "id") {
    return Some("\{path}.id must be a string or null")
  }
  guard fields.get("function") is Some(Object(function)) else {
    return Some("\{path}.function must be an object")
  }
  for name in ["name", "arguments"] {
    if !compatible_optional_string_field_is_valid(function, name) {
      return Some("\{path}.function.\{name} must be a string or null")
    }
  }
  compatible_thought_signature_validation_error(
    fields.get("extra_content"),
    path + ".extra_content",
  )
}

///|
fn compatible_stream_delta_validation_error(
  value : Json?,
  path : String,
) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      match fields.get("role") {
        None | Some(Null) | Some(String("assistant")) | Some(String("")) => ()
        _ => return Some("\{path}.role must be assistant, empty, or null")
      }
      for name in ["content", "reasoning_content", "reasoning"] {
        if !compatible_optional_string_field_is_valid(fields, name) {
          return Some("\{path}.\{name} must be a string or null")
        }
      }
      match fields.get("tool_calls") {
        None | Some(Null) => None
        Some(Array(values)) => {
          for index, tool_call in values {
            if compatible_stream_tool_call_validation_error(
                tool_call,
                path + ".tool_calls[" + index.to_string() + "]",
              )
              is Some(error) {
              return Some(error)
            }
          }
          None
        }
        _ => Some("\{path}.tool_calls must be an array or null")
      }
    }
    _ => Some("\{path} must be an object or null")
  }
}

///|
/// Validate one successful compatible-chat SSE value before state mutation.
pub fn validate_openai_compatible_chat_chunk(json : Json) -> String? {
  guard json is Object(fields) else {
    return Some("OpenAI-compatible stream chunk must be a JSON object")
  }
  if !compatible_optional_string_field_is_valid(fields, "id") ||
    !compatible_optional_string_field_is_valid(fields, "model") {
    return Some("OpenAI-compatible stream id and model must be strings or null")
  }
  if !compatible_optional_number_field_is_valid(fields, "created") {
    return Some("OpenAI-compatible stream created must be a number or null")
  }
  guard fields.get("choices") is Some(Array(choices)) else {
    return Some("OpenAI-compatible stream chunk must contain a choices array")
  }
  for index, choice in choices {
    guard choice is Object(choice_fields) else {
      return Some(
        "OpenAI-compatible stream choices[" +
        index.to_string() +
        "] must be an object",
      )
    }
    if !compatible_optional_string_field_is_valid(
        choice_fields, "finish_reason",
      ) {
      return Some(
        "OpenAI-compatible stream choices[" +
        index.to_string() +
        "].finish_reason must be a string or null",
      )
    }
    if compatible_stream_delta_validation_error(
        choice_fields.get("delta"),
        "OpenAI-compatible stream choices[" + index.to_string() + "].delta",
      )
      is Some(error) {
      return Some(error)
    }
  }
  compatible_usage_validation_error(
    fields.get("usage"),
    "OpenAI-compatible stream usage",
  )
}

///|
fn validate_openai_compatible_completion_choice(
  value : Json,
  path : String,
) -> String? {
  guard value is Object(fields) else {
    return Some("\{path} must be an object")
  }
  guard fields.get("text") is Some(String(_)) else {
    return Some("\{path}.text must be a string")
  }
  if !compatible_optional_string_field_is_valid(fields, "finish_reason") {
    return Some("\{path}.finish_reason must be a string or null")
  }
  if !compatible_optional_number_field_is_valid(fields, "index") {
    return Some("\{path}.index must be a number or null")
  }
  None
}

///|
fn validate_openai_compatible_completion_value(
  json : Json,
  path : String,
) -> String? {
  guard json is Object(fields) else {
    return Some("\{path} must be a JSON object")
  }
  if !compatible_optional_string_field_is_valid(fields, "id") ||
    !compatible_optional_string_field_is_valid(fields, "model") {
    return Some("\{path} id and model must be strings or null")
  }
  if !compatible_optional_number_field_is_valid(fields, "created") {
    return Some("\{path} created must be a number or null")
  }
  guard fields.get("choices") is Some(Array(choices)) else {
    return Some("\{path} must contain a choices array")
  }
  for index, choice in choices {
    if validate_openai_compatible_completion_choice(
        choice,
        path + ".choices[" + index.to_string() + "]",
      )
      is Some(error) {
      return Some(error)
    }
  }
  compatible_usage_validation_error(fields.get("usage"), path + ".usage")
}

///|
/// Validate a non-streaming compatible completion response before mapping it.
pub fn validate_openai_compatible_completion_response(json : Json) -> String? {
  validate_openai_compatible_completion_value(
    json, "OpenAI-compatible completion response",
  )
}

///|
/// Validate a compatible completion SSE value before mutating stream state.
pub fn validate_openai_compatible_completion_chunk(json : Json) -> String? {
  validate_openai_compatible_completion_value(
    json, "OpenAI-compatible completion stream chunk",
  )
}
