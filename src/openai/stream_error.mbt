///|
fn openai_stream_error_object(json : Json) -> Json? {
  match json {
    { "type": "response.failed", "response": { "error": error, .. }, .. } if !(error
      is Null) => Some(error)
    { "error": error, .. } if !(error is Null) => Some(error)
    { "type": "error", "message": String(_), .. } => Some(json)
    _ => None
  }
}

///|
fn openai_stream_error_discriminator(error : Json) -> String {
  let parts : Array[String] = []
  match error {
    { "code": String(value), .. } => parts.push(value)
    { "code": Number(value, ..), .. } => parts.push(value.to_int().to_string())
    _ => ()
  }
  if @provider_utils.json_string_field(error, "type") is Some(value) {
    parts.push(value)
  }
  parts.join(" ").to_lower()
}

///|
fn openai_stream_numeric_status(error : Json) -> Int? {
  match error {
    { "code": Number(value, ..), .. } => {
      let status = value.to_int()
      if status >= 400 && status <= 599 {
        Some(status)
      } else {
        None
      }
    }
    { "code": String(value), .. } =>
      try @string.parse_int(value) catch {
        _ => None
      } noraise {
        status =>
          if status >= 400 && status <= 599 {
            Some(status)
          } else {
            None
          }
      }
    _ => None
  }
}

///|
fn openai_stream_error_status(error : Json) -> Int {
  guard openai_stream_numeric_status(error) is None else {
    return openai_stream_numeric_status(error).unwrap()
  }
  let discriminator = openai_stream_error_discriminator(error)
  if discriminator.contains("insufficient_quota") ||
    discriminator.contains("rate_limit") {
    429
  } else if discriminator.contains("authentication") {
    401
  } else if discriminator.contains("permission") {
    403
  } else if discriminator.contains("not_found") {
    404
  } else if discriminator.contains("invalid") ||
    discriminator.contains("bad_request") ||
    discriminator.contains("context_length") {
    400
  } else if discriminator.contains("overload") {
    503
  } else if discriminator.contains("timeout") {
    504
  } else {
    500
  }
}

///|
fn openai_responses_stream_is_output(json : Json) -> Bool {
  let event_type = @provider_utils.json_string_field(json, "type").unwrap_or("")
  event_type != "" &&
  event_type != "response.created" &&
  event_type != "response.in_progress" &&
  event_type != "response.failed" &&
  event_type != "error" &&
  event_type != "unknown_chunk"
}

///|
priv struct OpenAIResponsesStreamGuard {
  mut accepted : Bool
  mut output : Bool
  mut started : Bool
}

///|
fn OpenAIResponsesStreamGuard::new() -> OpenAIResponsesStreamGuard {
  { accepted: false, output: false, started: false }
}

///|
fn OpenAIResponsesStreamGuard::validate(
  self : OpenAIResponsesStreamGuard,
  json : Json,
) -> Unit raise {
  if !self.started {
    match openai_stream_error_object(json) {
      Some(error) => {
        let message = @provider_utils.json_string_field(error, "message").unwrap_or(
          "OpenAI stream failed before any output was generated",
        )
        let status_code = openai_stream_error_status(error)
        raise @provider_utils.SseProviderError(
          message~,
          status_code~,
          response_body=json.stringify(),
          is_retryable=@provider_utils.is_retryable_status(status_code),
        )
      }
      None =>
        match json {
          { "choices": Array(_), .. } =>
            raise @provider_utils.SseProviderError(
              message="Received a Chat Completions stream while using the OpenAI Responses API. Use openai.chat(model_id) for Chat Completions-compatible endpoints.",
              status_code=400,
              response_body=json.stringify(),
              is_retryable=false,
            )
          _ => ()
        }
    }
  }
  let event_type = @provider_utils.json_string_field(json, "type").unwrap_or("")
  if event_type == "response.in_progress" {
    self.accepted = true
  }
  if openai_responses_stream_is_output(json) {
    self.output = true
  }
}

///|
fn OpenAIResponsesStreamGuard::is_accepted(
  self : OpenAIResponsesStreamGuard,
) -> Bool {
  self.accepted
}

///|
fn OpenAIResponsesStreamGuard::has_output(
  self : OpenAIResponsesStreamGuard,
) -> Bool {
  self.output
}

///|
fn OpenAIResponsesStreamGuard::mark_started(
  self : OpenAIResponsesStreamGuard,
) -> Unit {
  self.started = true
}
