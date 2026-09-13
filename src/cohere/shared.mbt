///|
fn cohere_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn cohere_request_headers(
  api_key~ : String,
  headers~ : Map[String, String],
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="COHERE_API_KEY",
    description="Cohere",
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
    ["ai-sdk/cohere/\{VERSION}"],
  )
}

///|
fn cohere_map_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("COMPLETE") | Some("STOP_SEQUENCE") => @provider.V4FinishStop
    Some("MAX_TOKENS") => @provider.V4FinishLength
    Some("ERROR") => @provider.V4FinishError
    Some("TOOL_CALL") => @provider.V4FinishToolCalls
    _ => @provider.V4FinishOther
  }
  { unified, raw, }
}

///|
/// Cohere reports usage under `billed_units`/`tokens` with plain totals.
fn cohere_usage(value : Json?) -> @provider.LanguageModelV4Usage {
  match value {
    Some(object) if object is Object(fields) => {
      let input_tokens = match fields.get("tokens") {
        Some({ "input_tokens": Number(value, ..), .. }) => value.to_int()
        _ => 0
      }
      let output_tokens = match fields.get("tokens") {
        Some({ "output_tokens": Number(value, ..), .. }) => value.to_int()
        _ => 0
      }
      {
        input_tokens: {
          total: Some(input_tokens),
          no_cache: Some(input_tokens),
          cache_read: None,
          cache_write: None,
        },
        output_tokens: {
          total: Some(output_tokens),
          text: Some(output_tokens),
          reasoning: None,
        },
        raw: Some(object),
      }
    }
    _ => @provider.LanguageModelV4Usage::unknown()
  }
}

///|
/// Flatten a Cohere document/image part payload into text or a data URI.
fn cohere_file_url(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
) -> String? raise {
  match data {
    @provider.V4FileUrl(url) => Some(url)
    @provider.V4FileData(payload) =>
      Some("data:\{media_type};base64,\{payload}")
    @provider.V4FileText(text) => Some(text)
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="file parts with provider references",
      )
  }
}
