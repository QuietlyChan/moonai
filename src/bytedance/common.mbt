///|
fn load_bytedance_api_key(
  api_key : String,
) -> String raise @provider.LoadAPIKeyError {
  @provider_utils.load_api_key(
    api_key,
    environment_variable_name="ARK_API_KEY",
    description="ByteDance ModelArk",
  )
}

///|
fn bytedance_headers(
  api_key : String,
  configured : Map[String, String],
  request : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let base : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("Accept-Encoding", "identity"),
    ("Authorization", "Bearer " + load_bytedance_api_key(api_key)),
  ])
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(base, configured),
      ["moonai/bytedance/\{VERSION}"],
    ),
    request,
  )
}

///|
fn bytedance_error_message(json : Json) -> String? raise {
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}
