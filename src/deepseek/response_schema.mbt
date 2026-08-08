///|
/// Validate the limited successful-response shape used by the DeepSeek V4
/// adapter. Unknown fields remain allowed so provider additions do not break
/// decoding.
fn deepseek_chat_response_validation_error(json : Json) -> String? {
  guard json is Object(fields) else {
    return Some("DeepSeek response must be a JSON object")
  }
  if !deepseek_optional_string_field_is_valid(fields, "id") ||
    !deepseek_optional_string_field_is_valid(fields, "model") {
    return Some("DeepSeek response id and model must be strings or null")
  }
  if !deepseek_optional_number_field_is_valid(fields, "created") {
    return Some("DeepSeek response created must be a number or null")
  }
  guard fields.get("choices") is Some(Array(choices)) else {
    return Some("DeepSeek response must contain a choices array")
  }
  for index, choice in choices {
    let choice_path = "DeepSeek response choices[" + index.to_string() + "]"
    guard choice is Object(choice_fields) else {
      return Some(choice_path + " must be an object")
    }
    if !deepseek_optional_string_field_is_valid(choice_fields, "finish_reason") {
      return Some(choice_path + ".finish_reason must be a string or null")
    }
    guard choice_fields.get("message") is Some(Object(message)) else {
      return Some(choice_path + ".message must be an object")
    }
    match message.get("role") {
      None | Some(Null) | Some(String("assistant")) => ()
      _ => return Some(choice_path + ".message.role must be assistant or null")
    }
    for name in ["content", "reasoning_content"] {
      if !deepseek_optional_string_field_is_valid(message, name) {
        return Some(
          choice_path + ".message." + name + " must be a string or null",
        )
      }
    }
    match message.get("tool_calls") {
      None | Some(Null) => ()
      Some(Array(tool_calls)) =>
        for tool_index, tool_call in tool_calls {
          let tool_path = choice_path +
            ".message.tool_calls[" +
            tool_index.to_string() +
            "]"
          guard tool_call is Object(tool_fields) else {
            return Some(tool_path + " must be an object")
          }
          if !deepseek_optional_string_field_is_valid(tool_fields, "id") {
            return Some(tool_path + ".id must be a string or null")
          }
          guard tool_fields.get("function") is Some(Object(function)) else {
            return Some(tool_path + ".function must be an object")
          }
          for name in ["name", "arguments"] {
            if !(function.get(name) is Some(String(_))) {
              return Some(tool_path + ".function." + name + " must be a string")
            }
          }
        }
      _ =>
        return Some(
          choice_path + ".message.tool_calls must be an array or null",
        )
    }
  }
  match fields.get("usage") {
    Some(value) => deepseek_usage_validation_error(value)
    None => None
  }
}

///|
/// Validate a successful HTTP response before it reaches the DeepSeek decoder.
fn validate_deepseek_chat_response(json : Json) -> Unit raise {
  if deepseek_chat_response_validation_error(json) is Some(error) {
    raise @provider.InvalidResponseDataError(
      message="Invalid DeepSeek Chat response: " + error,
      data=json,
    )
  }
}
