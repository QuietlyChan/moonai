///|
/// TogetherAI error payloads nest the human-readable message under `error`.
fn togetherai_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
fn togetherai_request_headers(
  provider_name~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="TOGETHER_API_KEY",
    description="TogetherAI",
  )
  let base : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer \{api_key}"),
  ])
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(base, headers),
    ["ai-sdk/\{provider_name}/\{VERSION}"],
  )
}
