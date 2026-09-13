///|
fn xai_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
fn xai_request_headers(
  api_key~ : String,
  headers~ : Map[String, String],
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="XAI_API_KEY",
    description="xAI",
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
    ["ai-sdk/xai/\{VERSION}"],
  )
}

///|
fn xai_map_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("stop") => @provider.V4FinishStop
    Some("length") => @provider.V4FinishLength
    Some("tool_calls") | Some("function_call") => @provider.V4FinishToolCalls
    Some("content_filter") => @provider.V4FinishContentFilter
    _ => @provider.V4FinishOther
  }
  { unified, raw, }
}

///|
fn xai_response_metadata(value : Json) -> @provider.ResponseMetadata {
  let mut id : String? = None
  let mut model_id : String? = None
  let mut created_at : Int? = None
  if value is Object(fields) {
    match fields.get("id") {
      Some(String(text)) => id = Some(text)
      _ => ()
    }
    match fields.get("model") {
      Some(String(text)) => model_id = Some(text)
      _ => ()
    }
    match fields.get("created") {
      Some(Number(value, ..)) => created_at = Some(value.to_int())
      _ => ()
    }
  }
  { ..@provider.ResponseMetadata::empty(), id, model_id, created_at, }
}

///|
fn xai_citations(value : Json) -> Array[String] {
  match value {
    { "citations": Array(urls), .. } => {
      let result : Array[String] = []
      for url in urls {
        if url is String(text) {
          result.push(text)
        }
      }
      result
    }
    _ => []
  }
}
