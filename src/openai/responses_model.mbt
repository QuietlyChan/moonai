///|
/// Official OpenAI Responses API model.
///
/// This type owns OpenAI-specific capability and option handling while reusing
/// the protocol decoder from `open_responses`.
priv struct OpenAIResponsesModel {
  provider_name : String
  url : String
  api_key : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
}

///|
fn OpenAIResponsesModel::request_headers_with(
  self : OpenAIResponsesModel,
  extra_headers : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/openai/\{VERSION}"],
    ),
    extra_headers,
  )
}
