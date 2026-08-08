///|
fn alibaba_optional_string_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(String(_)) => true
    _ => false
  }
}

///|
fn alibaba_optional_number_field_is_valid(
  fields : Map[String, Json],
  name : String,
) -> Bool {
  match fields.get(name) {
    None | Some(Null) | Some(Number(_)) => true
    _ => false
  }
}

///|
fn alibaba_usage_details_validation_error(
  value : Json?,
  path : String,
  names : Array[String],
) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      for name in names {
        if !alibaba_optional_number_field_is_valid(fields, name) {
          return Some("\{path}.\{name} must be a number or null")
        }
      }
      None
    }
    _ => Some("\{path} must be an object or null")
  }
}

///|
fn alibaba_usage_validation_error(value : Json?, path : String) -> String? {
  match value {
    None | Some(Null) => None
    Some(Object(fields)) => {
      for name in ["prompt_tokens", "completion_tokens", "total_tokens"] {
        if !(fields.get(name) is Some(Number(_))) {
          return Some("\{path}.\{name} must be a number")
        }
      }
      if alibaba_usage_details_validation_error(
          fields.get("prompt_tokens_details"),
          path + ".prompt_tokens_details",
          ["cached_tokens", "cache_creation_input_tokens"],
        )
        is Some(error) {
        return Some(error)
      }
      alibaba_usage_details_validation_error(
        fields.get("completion_tokens_details"),
        path + ".completion_tokens_details",
        ["reasoning_tokens"],
      )
    }
    _ => Some("\{path} must be an object or null")
  }
}

///|
fn alibaba_response_tool_calls_validation_error(
  value : Json?,
  path : String,
) -> String? {
  match value {
    None | Some(Null) => None
    Some(Array(values)) => {
      for index, value in values {
        let item_path = path + "[" + index.to_string() + "]"
        guard value is Object(fields) else {
          return Some("\{item_path} must be an object")
        }
        if !(fields.get("id") is Some(String(_))) {
          return Some("\{item_path}.id must be a string")
        }
        if !(fields.get("type") is Some(String("function"))) {
          return Some("\{item_path}.type must be function")
        }
      }
      None
    }
    _ => Some("\{path} must be an array or null")
  }
}

///|
fn validate_alibaba_chat_response(json : Json) -> String? {
  if @openai_compatible.validate_openai_compatible_chat_response(json)
    is Some(error) {
    return Some(error)
  }
  guard json is Object(fields) && fields.get("choices") is Some(Array(choices)) else {
    return Some("Alibaba response must contain a choices array")
  }
  for index, choice in choices {
    guard choice is Object(choice_fields) else {
      return Some("Alibaba response choice must be an object")
    }
    if !(choice_fields.get("index") is Some(Number(_))) {
      return Some(
        "Alibaba response choices[" +
        index.to_string() +
        "].index must be a number",
      )
    }
    guard choice_fields.get("message") is Some(Object(message)) else {
      return Some("Alibaba response choice.message must be an object")
    }
    if alibaba_response_tool_calls_validation_error(
        message.get("tool_calls"),
        "Alibaba response choices[" + index.to_string() + "].message.tool_calls",
      )
      is Some(error) {
      return Some(error)
    }
  }
  alibaba_usage_validation_error(fields.get("usage"), "Alibaba response usage")
}

///|
fn alibaba_stream_tool_calls_validation_error(
  value : Json?,
  path : String,
) -> String? {
  match value {
    None | Some(Null) => None
    Some(Array(values)) => {
      for index, value in values {
        let item_path = path + "[" + index.to_string() + "]"
        guard value is Object(fields) else {
          return Some("\{item_path} must be an object")
        }
        if !alibaba_optional_number_field_is_valid(fields, "index") ||
          !alibaba_optional_string_field_is_valid(fields, "id") {
          return Some("\{item_path}.index and id have invalid types")
        }
        match fields.get("type") {
          None | Some(Null) | Some(String("function")) => ()
          _ => return Some("\{item_path}.type must be function or null")
        }
        match fields.get("function") {
          None | Some(Null) => ()
          Some(Object(function)) =>
            for name in ["name", "arguments"] {
              if !alibaba_optional_string_field_is_valid(function, name) {
                return Some(
                  "\{item_path}.function.\{name} must be a string or null",
                )
              }
            }
          _ => return Some("\{item_path}.function must be an object or null")
        }
      }
      None
    }
    _ => Some("\{path} must be an array or null")
  }
}

///|
fn validate_alibaba_chat_chunk(json : Json) -> String? {
  guard json is Object(fields) else {
    return Some("Alibaba stream chunk must be a JSON object")
  }
  if !alibaba_optional_string_field_is_valid(fields, "id") ||
    !alibaba_optional_string_field_is_valid(fields, "model") ||
    !alibaba_optional_number_field_is_valid(fields, "created") {
    return Some("Alibaba stream metadata fields have invalid types")
  }
  guard fields.get("choices") is Some(Array(choices)) else {
    return Some("Alibaba stream chunk must contain a choices array")
  }
  for index, choice in choices {
    let choice_path = "Alibaba stream choices[" + index.to_string() + "]"
    guard choice is Object(choice_fields) else {
      return Some("\{choice_path} must be an object")
    }
    if !(choice_fields.get("index") is Some(Number(_))) {
      return Some("\{choice_path}.index must be a number")
    }
    if !alibaba_optional_string_field_is_valid(choice_fields, "finish_reason") {
      return Some("\{choice_path}.finish_reason must be a string or null")
    }
    guard choice_fields.get("delta") is Some(Object(delta)) else {
      return Some("\{choice_path}.delta must be an object")
    }
    match delta.get("role") {
      None | Some(Null) | Some(String("assistant")) => ()
      _ => return Some("\{choice_path}.delta.role must be assistant or null")
    }
    for name in ["content", "reasoning_content"] {
      if !alibaba_optional_string_field_is_valid(delta, name) {
        return Some("\{choice_path}.delta.\{name} must be a string or null")
      }
    }
    if alibaba_stream_tool_calls_validation_error(
        delta.get("tool_calls"),
        choice_path + ".delta.tool_calls",
      )
      is Some(error) {
      return Some(error)
    }
  }
  alibaba_usage_validation_error(fields.get("usage"), "Alibaba stream usage")
}
