///|
fn perplexity_error_to_message(json : Json) -> String? raise {
  @provider.check_cancellation(None)
  match json {
    { "error": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": { "type": String(kind), .. }, .. } => Some(kind)
    { "detail": String(message), .. } => Some(message)
    { "detail": Array(details), .. } => {
      let messages : Array[String] = []
      for detail in details {
        match detail {
          { "msg": String(message), .. } => messages.push(message)
          _ => ()
        }
      }
      if messages.length() == 0 {
        None
      } else {
        Some(messages.join(", "))
      }
    }
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn perplexity_request_headers(
  api_key~ : String,
  headers~ : Map[String, String],
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="PERPLEXITY_API_KEY",
    description="Perplexity",
  )
  let base : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer \{api_key}"),
  ])
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(base, headers),
      extra,
    ),
    ["ai-sdk/perplexity/\{VERSION}"],
  )
}

///|
fn perplexity_map_agent_finish_reason(
  status : String,
  incomplete_reason : String?,
  has_function_call : Bool,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match incomplete_reason {
    Some("max_output_tokens") => @provider.V4FinishLength
    Some("content_filter") => @provider.V4FinishContentFilter
    _ =>
      match status {
        "completed" =>
          if has_function_call {
            @provider.V4FinishToolCalls
          } else {
            @provider.V4FinishStop
          }
        "requires_action" => @provider.V4FinishToolCalls
        "failed" => @provider.V4FinishError
        _ =>
          if has_function_call {
            @provider.V4FinishToolCalls
          } else {
            @provider.V4FinishOther
          }
      }
  }
  let raw = match incomplete_reason {
    Some(reason) => Some(reason)
    None => Some(status)
  }
  { unified, raw, }
}
